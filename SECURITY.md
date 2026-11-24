# Security policy

## Reporting a vulnerability

Please do **not** open a public issue. Use **[Report a vulnerability](https://github.com/Jano-Projects/aviation-otp-observatory/security/advisories/new)** in the *Security* tab: the report is visible only to the maintainer.

Describe what happens, how to reproduce it and which version or commit you used. You will get an answer within a few days, and the fix will credit you if you wish.

## How the project handles secrets

- Passwords live only in `.env`, which is git-ignored. `.env.example` holds **example** passwords for a local container: change them before exposing anything beyond your machine.
- Containers publish their ports on `127.0.0.1` only. Opening them to a network is outside the scope of this project.
- No credentials, wallets or personal data are part of the repository or its history.

## Supported versions

Only the latest commit on `main` receives fixes.
