#!/usr/bin/env bash
# Shared Windows code signing for every project: one Azure Artifact Signing (formerly Trusted
# Signing) account, one certificate profile, and one secretless app registration that GitHub
# Actions reaches through OIDC. Idempotent. Needs `az login` (an interactive login satisfies MFA).
#
#   bash ci/azure/signing.sh setup                 # account + app registration + role
#   bash ci/azure/signing.sh profile [VALIDATION_ID]  # certificate profile, after identity validation
#   bash ci/azure/signing.sh trust OWNER/REPO      # let a repo's `release` environment sign
set -Eeuo pipefail

RG=${SIGNING_RG:-rg-shared-signing}
LOCATION=${SIGNING_LOCATION:-northeurope}  # westeurope stopped taking new Artifact Signing customers (Oct 2026)
ACCOUNT=${SIGNING_ACCOUNT:-kingsidharth-signing}
PROFILE=${SIGNING_PROFILE:-public-trust}
APP_NAME=${SIGNING_APP:-github-actions-artifact-signing}
ROLE="Artifact Signing Certificate Profile Signer"
LEGACY_ROLE="Trusted Signing Certificate Profile Signer"

az extension add --upgrade --only-show-errors -n trustedsigning >/dev/null
account_id() { az trustedsigning show -g "$RG" -n "$ACCOUNT" --query id -o tsv; }
app_id() { az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv; }

setup() {
  az provider register -n Microsoft.CodeSigning --wait
  # A group's own region doesn't bind its resources, so an existing group is reused wherever it is.
  az group show -n "$RG" >/dev/null 2>&1 || az group create -n "$RG" -l "$LOCATION" --tags purpose=shared-code-signing >/dev/null
  az trustedsigning show -g "$RG" -n "$ACCOUNT" >/dev/null 2>&1 ||
    az trustedsigning create -g "$RG" -n "$ACCOUNT" -l "$LOCATION" --sku Basic >/dev/null
  [[ -n $(app_id) ]] || az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg >/dev/null
  local app sp role
  app=$(app_id)
  sp=$(az ad sp show --id "$app" --query id -o tsv 2>/dev/null || az ad sp create --id "$app" --query id -o tsv)
  role=$ROLE
  az role definition list --name "$role" --query '[0].name' -o tsv | grep -q . || role=$LEGACY_ROLE
  az role assignment create --assignee-object-id "$sp" --assignee-principal-type ServicePrincipal \
    --role "$role" --scope "$(account_id)" >/dev/null
  cat <<EOF

Account ready. Next, validate your identity in the portal (Objects > Identity validations > New identity):
  https://portal.azure.com/#@/resource$(account_id)/overview
Once it shows Completed, run: bash ci/azure/signing.sh profile

GitHub repository variables for each project that signs Windows builds:
  AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
  AZURE_CLIENT_ID=$app
  AZURE_SIGNING_ENDPOINT=$(az trustedsigning show -g "$RG" -n "$ACCOUNT" --query accountUri -o tsv | sed 's:/*$::')
  AZURE_SIGNING_ACCOUNT=$ACCOUNT
  AZURE_SIGNING_PROFILE=$PROFILE
EOF
}

# $1: the identity validation ID shown in the portal (Identity validations > your entry).
profile() {
  local validation=${1:-}
  [[ -n $validation ]] || validation=$(az rest --method get \
    --url "https://management.azure.com$(account_id)/identityValidations?api-version=2024-09-30-preview" \
    --query "value[?properties.status=='Completed'] | [0].name" -o tsv 2>/dev/null || true)
  [[ -n $validation ]] || {
    echo "No completed identity validation found. Finish it in the portal, then pass its ID: signing.sh profile <id>" >&2
    exit 1
  }
  az trustedsigning certificate-profile show -g "$RG" --account-name "$ACCOUNT" -n "$PROFILE" >/dev/null 2>&1 ||
    az trustedsigning certificate-profile create -g "$RG" --account-name "$ACCOUNT" -n "$PROFILE" \
      --profile-type PublicTrust --identity-validation-id "$validation" >/dev/null
  echo "Certificate profile '$PROFILE' ready."
}

trust() {
  local repo=${1:?OWNER/REPO} app name
  [[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "bad repo '$repo'" >&2; exit 1; }
  # The federated credential trusts the `release` environment, so that environment must only
  # admit v* tags. GitHub creates environments unprotected on first use, so set it here.
  gh api -X PUT "repos/$repo/environments/release" --input - >/dev/null <<<'{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
  gh api "repos/$repo/environments/release/deployment-branch-policies" --jq '.branch_policies[] | "\(.type) \(.name)"' |
    grep -qx "tag v\*" || gh api -X POST "repos/$repo/environments/release/deployment-branch-policies" -f name='v*' -f type=tag >/dev/null
  app=$(app_id)
  name="gh-$(tr -c 'A-Za-z0-9-' '-' <<<"$repo" | sed 's/-*$//')-release"
  az ad app federated-credential list --id "$app" --query "[?name=='$name'].name" -o tsv | grep -q . && return 0
  az ad app federated-credential create --id "$app" --parameters "$(jq -cn --arg n "$name" --arg s "repo:${repo}:environment:release" \
    '{name: $n, issuer: "https://token.actions.githubusercontent.com", subject: $s, audiences: ["api://AzureADTokenExchange"]}')" >/dev/null
  echo "$repo's release environment can now sign."
}

case ${1:-} in
  setup) setup ;;
  profile) profile "${2:-}" ;;
  trust) trust "${2:-}" ;;
  *) sed -n '2,10p' "$0"; exit 64 ;;
esac
