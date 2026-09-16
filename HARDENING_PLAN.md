# Production hardening plan

Written 2026-09-17, after the first real production launch. Three
independent workstreams — pick any one and hand it to a fresh Claude Code
session (or do it yourself) without needing the others done first. None of
this has been started yet except where noted.

Context this plan assumes you already have: production is live at
`tickets.festival.in.th` / `accounts.festival.in.th` / `api.festival.in.th`,
on GCP project `festival-508622`, region `asia-southeast1`. Terraform lives
in `tickets-infra/terraform`, one `environment` module instantiated twice
(`staging`, `production`). See `tickets-infra/HANDOFF.md` for how to
actually deploy/operate day to day — this file is just the hardening
roadmap.

---

## 1. Cloud Armor (WAF + rate limiting at the edge)

**Status: not started.** Currently each Cloud Run service has its own
custom domain mapping (`google_cloud_run_v2_service` + a Cloud Run domain
mapping) — there's no load balancer in front of them, and Cloud Armor only
attaches to a Global External Application Load Balancer. The app already
has in-process rate limiting (`@nestjs/throttler`, see each repo's
`app.module.ts` — 100 req/min/IP default, tighter overrides on
login/OTP/checkout) as a stopgap, but that's per-instance and per-service,
not a real edge defense against a distributed attack.

**What this actually requires** (real infra change, real recurring cost —
get sign-off on the ~$18-25/mo forwarding-rule cost before applying):

1. A Global External Application Load Balancer (`google_compute_global_forwarding_rule`,
   `google_compute_target_https_proxy`, `google_compute_url_map`) in front
   of the 3 production Cloud Run services, using Serverless NEGs
   (`google_compute_region_network_endpoint_group`, one per service,
   `network_endpoint_type = "SERVERLESS"`).
2. Move the managed SSL cert + domain mapping from Cloud Run's own domain
   mapping over to the load balancer (`google_compute_managed_ssl_certificate`).
   This is the fiddly part — DNS needs to repoint from Cloud Run's
   `ghs.googlehosted.com` CNAME to the LB's static IP, and there will be a
   brief cutover window. Do this during a low-traffic window, staging
   first, watch it work for a few days before touching production DNS.
3. A `google_compute_security_policy` (the actual Cloud Armor resource)
   with:
   - A rate-limit rule (`rate_based_ban` action) tuned tighter than the
     in-app throttler, since this catches a distributed attack the
     per-instance in-app limiter can't see
   - The OWASP preconfigured WAF rules GCP ships (SQLi, XSS, RCE
     signatures) — start in preview mode, watch for false positives
     against real traffic for a week before switching to block mode
   - Attach the policy to the backend service(s) via `security_policy` on
     `google_compute_backend_service`
4. Keep the in-app throttler as-is — it's the backstop for whatever gets
   past Cloud Armor or hits a Cloud Run service directly if the LB
   migration has a gap.

Do this in a new `terraform/modules/environment/load_balancer.tf` (or a
root-level file, since a global LB isn't naturally per-environment — worth
deciding staging even needs one before building it twice).

## 2. Load testing

**Status: not started — no load test has ever been run against this app.**

Use k6 (or similar) against **staging only, never production**. The
concurrency unit test (`tickets-api/src/orders/checkout.concurrency.spec.ts`)
already proves the *locking logic* is correct at the code level; a load
test proves the *deployed infrastructure* (Cloud Run autoscaling, Cloud
SQL connection limits, Redis) holds up under real concurrent traffic —
different question.

Suggested scenario, modeling an on-sale traffic spike:
1. Ramp to some target concurrent virtual users (pick a number based on
   the biggest real event you expect — if you don't know, start with 200
   and see where it breaks) hitting: browse event → select tickets →
   create hold → pay (Omise test mode) in a loop.
2. Watch the new Cloud Monitoring dashboards
   (`tickets-infra`'s `monitoring_dashboard_urls` Terraform output) during
   the run — p95 latency, 5xx rate, container CPU/memory, instance count.
3. Specifically verify: no overselling (compare tickets sold vs.
   `quantityTotal` after the run — this is the exact invariant the
   concurrency unit test protects, now under real infra), Cloud SQL
   connection pool doesn't exhaust (`festival_tickets`'s Prisma connection
   pool size vs. Cloud SQL's max connections — check both are sized
   consistently), Redis (used for OTP attempt-lockout) doesn't become a
   bottleneck.
4. Record the breaking point (whatever concurrency level first shows
   errors or oversells) — that's the number that matters for "can we
   handle event X's on-sale."

## 3. Security review pass

**Status: partially done earlier in the project (auth flows, webhook
verification, RBAC) — needs a fresh pass over what's been added since,
specifically:**

- The two new internal service-to-service endpoints added 2026-09-17:
  `tickets-api`'s `POST /internal/owners`, `DELETE /internal/owners/:userId`,
  and the new `festival-auth-service`'s `GET /internal/users` — all guarded
  by a shared `x-internal-secret` header compared against
  `INTERNAL_SERVICE_SECRET`. Confirm: the secret is actually strong
  (32+ random bytes, not something guessable), never logged, and this
  guard pattern doesn't have a timing-attack issue (`!==` string
  comparison on a secret is technically timing-unsafe — low real risk here
  since it's not a per-request user-facing auth path, but worth a
  `crypto.timingSafeEqual` swap if being thorough).
- The CSV export endpoints (`GET /events/:id/export.csv`,
  `GET /admin/events/:id/export.csv`) return real buyer PII + payment
  provider refs in one unauthenticated-feeling download link. Confirm
  the JWT guard is actually enforced end to end (it is, per the code —
  `@UseGuards(JwtAuthGuard, RolesGuard)` — but re-verify no browser
  caching/CDN layer could serve a cached copy to a different signed-in
  user; Cloud Run doesn't cache responses by default, but worth
  confirming `Cache-Control` isn't accidentally permissive here).
- Re-confirm the Omise webhook's shared-secret query param
  (`OMISE_WEBHOOK_SHARED_SECRET`) is actually set in both environments —
  the code allows it to be unset (skips the check entirely), which was a
  deliberate "local dev doesn't need it" default but must not be true in
  staging/production.
- General secrets-hygiene re-check: grep both repos' code for any
  `console.log`/`Logger.error` call that might include a full request
  body or error object that could contain a token, card number, or the
  internal secret.

Output should be a short written summary (findings + fixes made), same
format as the earlier pass, not a new subsystem.

---

## Suggested order

Security review pass (3) has no infra dependency and no cost — do it
first, any time, in any session. Load testing (2) should happen before
Cloud Armor (1) so you have a real baseline of how the app behaves without
edge protection, and Cloud Armor is easiest to build with a load test
already scripted (reuse it to validate the rate-limit rule doesn't block
legitimate traffic).
