# Terraform — festival-508622

Provisions the shared VPC, Cloud SQL, Memorystore, Secret Manager slots,
Artifact Registry, Cloud Run services, and Workload Identity Federation for
GitHub Actions — one `staging` and one `production` copy of everything via
the `modules/environment` module (see `environments.tf`).

## What this does NOT do

- Populate real secret values (Omise keys, Mailgun key, Firebase Web SDK
  config, JWT signing key) — Terraform creates empty slots
  (`secrets.tf`'s `manual_secret_ids`) with a `REPLACE_ME` placeholder.
  Populate for real with:
  ```bash
  gcloud secrets versions add <secret-id> --data-file=- --project=festival-508622
  ```
- Deploy real application images — every Cloud Run service starts on the
  public `gcr.io/cloudrun/hello` placeholder image
  (`lifecycle { ignore_changes = [...] }` stops future `apply`s from
  reverting whatever the GitHub Actions deploy pipeline pushes later)
- DNS — per `manual-setup-tasks.md`, pointing `tickets.festival.in.th` /
  `accounts.festival.in.th` at the Cloud Run domain mappings this creates
  stays a manual step
- Load testing, Cloud Armor, Cloud Monitoring dashboards — later Phase 6
  items, not infra provisioning

## Usage

```bash
cd terraform
terraform init
terraform plan    # review before ever applying — nothing here is applied automatically
terraform apply
```

Needs Application Default Credentials for a principal with Owner (or
equivalent) on `festival-508622`:

```bash
gcloud auth application-default login
```

## Structure

- `apis.tf` — enables every GCP API this config needs
- `network.tf` — shared VPC, subnet, Serverless VPC Access connector,
  private services access (Memorystore requires the latter)
- `artifact_registry.tf` — one shared Docker repo, images tagged by
  service name so a build validated in staging can be promoted to
  production by tag
- `wif.tf` — Workload Identity Federation, scoped to this repo owner's
  repos AND main-branch pushes only (a PR build or fork can never
  authenticate through this)
- `environments.tf` — instantiates `modules/environment` twice
- `modules/environment/` — everything that's genuinely per-environment:
  Cloud SQL instance + 2 databases, Memorystore, secret slots (including
  the ones Terraform *can* generate itself — `internal_service_secret`,
  `omise_webhook_shared_secret`), 3 service accounts (least-privilege,
  scoped to only the secrets/Cloud SQL each service needs), 3 Cloud Run
  services, domain mappings (production only)

## Cross-service URLs and the dependency cycle

`festival-auth-service` needs `tickets-api`'s address (internal
registration calls); `tickets-api` needs `festival-auth-service`'s address
(JWKS verification). That's a real cycle if both sides reference the
other's dynamically-assigned Cloud Run `.uri`. Broken by having
`tickets-api` (and `tickets-web`) reference `festival-auth-service`'s
**stable custom domain** (a plain string — no Terraform dependency on the
`auth_service` resource) while `festival-auth-service` references
`tickets-api`'s real `.uri` (a genuine dependency — `tickets-api` gets
created first). Staging gets a `staging.`-prefixed version of the same
domain strings for the same reason, even though no domain mapping is
actually created for staging yet.
