# tickets-infra

Shared local dev stack + (later) Terraform/GitHub Actions templates for
`festival-auth-service`, `tickets-api`, and `tickets-web`.

## Local ports

| Service                          | Port  | Notes                                  |
|-----------------------------------|-------|-----------------------------------------|
| Postgres                          | 5442  | host → container 5432                   |
| Redis                              | 6390  | host → container 6379                   |
| Firebase Auth emulator             | 9099  | phone OTP, fully offline (`demo-festival`) |
| Firebase Firestore emulator        | 8090  |                                          |
| Firebase Emulator UI               | 4460  | http://localhost:4460 (4400 was taken on this machine) |
| festival-auth-service (API)        | 3401  |                                          |
| tickets-api                        | 3402  |                                          |
| tickets-web                        | 3434  |                                          |

All chosen to avoid the common 3000/5432/6379/8080 defaults other local
projects on this machine are likely already using.

## Start the stack

```bash
docker compose up -d
npx firebase-tools emulators:start
```

The Firebase project id is `demo-festival` — a `demo-`-prefixed project id
runs the emulator fully offline with no real Firebase project required, so
phone OTP is testable right now without waiting on the real project setup
in `manual-setup-tasks.md`. Swap `.firebaserc` to the real project id later
if you want the emulator to mirror the actual project (e.g. before staging).

## Databases

One Postgres container, two databases (`scripts/init-databases.sql`):
- `festival_auth` — owned by `festival-auth-service`
- `festival_tickets` — owned by `tickets-api`

Keeps the identity/ticketing data boundary clean without running two
containers locally.
