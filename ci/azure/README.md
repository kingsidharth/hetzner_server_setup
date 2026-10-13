# Azure: shared Windows signing and on-demand QA

Both scripts need `az login` first. An interactive login satisfies the tenant's MFA
security defaults; a stale CLI token fails with `AADSTS530035`.

## Code signing for every project (`signing.sh`)

```bash
bash ci/azure/signing.sh setup                    # account, app registration, role
# validate your identity in the portal (link printed by setup), then:
bash ci/azure/signing.sh profile [VALIDATION_ID]  # certificate profile
bash ci/azure/signing.sh trust OWNER/REPO         # once per project
```

- One **Artifact Signing** account (`kingsidharth-signing`, Basic SKU, West Europe, endpoint
  `https://weu.codesigning.azure.net`) and one Public Trust **certificate profile** serve
  every project.
- GitHub Actions signs **without a stored secret**. An app registration
  (`github-actions-artifact-signing`) holds the "Artifact Signing Certificate Profile
  Signer" role on the account and trusts each repo's `release` environment through a
  federated credential (`repo:OWNER/REPO:environment:release`). Only jobs in that
  environment, which only `v*` tags can enter, can get a signing token. Add a project
  with `trust`; up to 20 per app registration.
- Signing happens from Linux with jsign (`--storetype TRUSTEDSIGNING`), in the
  `ci-windows` image.

**Identity validation** is manual and done by you: portal > the signing account >
**Objects > Identity validations > New identity > Public**. Organisations need a legal
entity with verifiable business records; individual validation has been limited to some
countries, so check that it's offered for yours before relying on it.

## Windows QA VM (`qa-vm.sh`)

```bash
bash ci/azure/qa-vm.sh up     # Windows Server 2025, RDP only from your current IP
bash ci/azure/qa-vm.sh down   # deletes the whole resource group
```

Connect with Windows App (Remote Desktop) on the Mac. The password is generated into
`~/.config/winqa/password` (0600) and never printed. Delete the VM after each QA run.

## Monthly cost

| Resource | Cost |
| --- | --- |
| Resource group `rg-shared-signing` | free |
| Artifact Signing account, Basic | $9.99 / month, includes 5,000 signatures (then $0.005 each) |
| Certificate profile | included |
| App registration, service principal, federated credentials, role assignment | free |
| QA VM `Standard_B2ms` (Windows license included) + 127 GB OS disk + public IP | about $0.20 / hour while it exists, $0 after `down` |

Typical total: **about $10 / month**, plus about $0.20 per hour of QA. These are list-price
estimates; check the Azure pricing calculator for your region and currency.
