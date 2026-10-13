#!/usr/bin/env bash
# On-demand Windows VM for desktop QA (e.g. Codex computer use through Windows App / RDP).
# `up` creates everything in its own resource group; `down` deletes the whole group, so an
# idle QA setup costs nothing. RDP is open only to the public IP that ran `up`.
#
#   bash ci/azure/qa-vm.sh up       # prints host, user and where the password was saved
#   bash ci/azure/qa-vm.sh down
set -Eeuo pipefail

RG=${QA_RG:-rg-shared-winqa}
LOCATION=${QA_LOCATION:-westeurope}
VM=${QA_VM:-winqa}
SIZE=${QA_SIZE:-Standard_B2ms}  # 2 vCPU / 8 GB: enough for an Electron app
IMAGE=MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition:latest # license included
USER_NAME=qa
SECRET_FILE=${QA_SECRET_FILE:-$HOME/.config/winqa/password}

up() {
  local me ip
  me=$(curl -fsS https://api.ipify.org)
  [[ $me =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "couldn't determine this machine's public IPv4" >&2; exit 1; }
  mkdir -p "$(dirname "$SECRET_FILE")" && chmod 700 "$(dirname "$SECRET_FILE")"
  if [[ ! -s $SECRET_FILE ]]; then
    (umask 077 && printf '%s' "Qa-$(openssl rand -base64 30 | tr -dc A-Za-z0-9 | head -c 24)!9" >"$SECRET_FILE")
  fi
  az group create -n "$RG" -l "$LOCATION" --tags purpose=windows-qa >/dev/null
  az vm create -g "$RG" -n "$VM" --image "$IMAGE" --size "$SIZE" \
    --admin-username "$USER_NAME" --admin-password "@$SECRET_FILE" \
    --public-ip-sku Standard --nsg-rule NONE --os-disk-delete-option Delete --only-show-errors >/dev/null
  az network nsg rule create -g "$RG" --nsg-name "${VM}NSG" -n rdp-from-me --priority 1000 \
    --source-address-prefixes "$me/32" --destination-port-ranges 3389 --protocol Tcp --access Allow >/dev/null
  ip=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
  echo "RDP: $ip:3389  user: $USER_NAME  password: in $SECRET_FILE"
  echo "Delete when done: bash ci/azure/qa-vm.sh down"
}

down() {
  # Only ever delete the group this script created.
  [[ $(az group show -n "$RG" --query tags.purpose -o tsv 2>/dev/null) == windows-qa ]] ||
    { echo "$RG isn't tagged purpose=windows-qa; not deleting it" >&2; exit 1; }
  az group delete -n "$RG" --yes --no-wait
  echo "Deleting $RG (VM, disk, IP, network). Nothing left running."
}

case ${1:-} in
  up) up ;;
  down) down ;;
  *) sed -n '2,8p' "$0"; exit 64 ;;
esac
