# Staging → production deploy checklist

Written against what exists today (Slice A: code-level hardening, no cloud
infra yet). Sections marked **(Slice B)** assume infra that doesn't exist
yet — Cloud Run, Cloud SQL, Secret Manager, Workload Identity Federation.
Fill those in as Slice B lands rather than treating this as final.

## Before every deploy (staging or production)

- [ ] CI is green on the commit being deployed (`.github/workflows/ci.yml`
      in each repo — lint/build + test, including the concurrency suite in
      `tickets-api`)
- [ ] `npm audit` reviewed for new high/critical findings since the last
      deploy (not auto-blocking, but don't ship a new critical silently)
- [ ] Database migrations for this commit are backward-compatible with the
      *currently running* code, if this is a rolling deploy (Cloud Run
      default) — a migration that drops/renames a column the old revision
      still reads will break requests mid-rollout
- [ ] Required secrets exist in Secret Manager for the target environment
      **(Slice B)**: `OMISE_SECRET_KEY`, `OMISE_PUBLIC_KEY`,
      `OMISE_WEBHOOK_SHARED_SECRET`, `MAILGUN_API_KEY`,
      `INTERNAL_SERVICE_SECRET`, JWT signing keypair (`KEYS_DIR` mount),
      Firebase Admin SDK credentials, `FIREBASE_API_KEY`/`FIREBASE_AUTH_DOMAIN`
- [ ] `FIREBASE_AUTH_EMULATOR_HOST` is **unset** in the target environment's
      config — if it's set, the service silently talks to the emulator
      instead of real Firebase (see `firebase-admin.service.ts` /
      `app.controller.ts`'s `/firebase-config.js`)

## Staging deploy **(Slice B)**

- [ ] `terraform apply` (or CI/CD pipeline) deploys the new image to the
      staging Cloud Run service
- [ ] Smoke test immediately after: sign in as a test buyer (OTP), browse
      an event, complete a test-mode checkout end-to-end, confirm the QR
      ticket page renders
- [ ] Smoke test the owner side: log in, view the dashboard, issue a test
      refund
- [ ] Confirm `/health` (both `tickets-api` and `festival-auth-service`)
      returns 200
- [ ] Watch Cloud Monitoring / logs for 5–10 minutes for unexpected error
      rates before calling staging "good"

## Production promotion **(Slice B)**

- [ ] Staging has been running the exact commit being promoted for at
      least [X hours — decide before first real promotion]
- [ ] Load test results from staging reviewed and signed off (Phase 6 —
      simulates an on-sale traffic spike, per
      `claude-code-implementation-plan.md`)
- [ ] Backup/restore drill has been run against the *real* Cloud SQL
      instance at least once (reuses `scripts/backup-restore.sh`'s logic —
      see that script's header)
- [ ] DNS confirmed pointing at the right target (manual, per
      `manual-setup-tasks.md`)
- [ ] Deploy during a low-traffic window unless there's a specific reason
      not to
- [ ] Run the same smoke tests as staging, against production, immediately
      after promotion
- [ ] Announce/monitor for the first 30 minutes post-deploy before
      considering it done

## Rollback

**(Slice B, Cloud Run-specific)** Cloud Run keeps prior revisions
available by default — rollback is:

```bash
gcloud run services update-traffic <service> --to-revisions=<previous-revision>=100
```

- [ ] Know the previous good revision name *before* starting a deploy (note
      it down, don't rely on remembering)
- [ ] A schema migration that isn't backward-compatible (see "before every
      deploy" above) makes a Cloud Run traffic rollback alone insufficient
      — the database also needs to roll back or the migration needs a
      forward-fix instead. Decide which per-incident; don't blanket-revert
      a migration against a database with new data already written under
      the new schema.
- [ ] After rolling back, re-run the smoke tests above against the rolled-
      back revision before calling the incident resolved

## Known gaps as of this checklist's writing

- No Terraform yet — Cloud SQL/Memorystore/Secret Manager/Cloud Run/WIF are
  all Slice B, not started
- No load testing has been run (needs staging to exist first)
- `eslint` is referenced by `tickets-api`/`festival-auth-service`'s `lint`
  npm script but was never actually installed — CI currently skips linting
  entirely (see each repo's `.github/workflows/ci.yml` comment)
- Backup/restore has only been dry-run locally (`scripts/backup-restore.sh`
  against the Docker Compose Postgres) — not yet against real Cloud SQL
