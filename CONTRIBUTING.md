# Contributing

Thanks for your interest in Aviation OTP Observatory. Issues and pull requests are welcome, in English or Portuguese.

## Issues

Open an issue with one of the templates:

- **Bug report**: something fails or gives a wrong result. Include the output of the command that failed and your environment (OS, Docker version, database version from `select banner_full from v$version`).
- **Feature request**: an idea, starting from the problem it solves.

Never paste passwords, `.env` files or personal data. Security problems go through the [security policy](SECURITY.md), not public issues.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Keep each pull request focused on one change, and update the documentation and `CHANGELOG.md` (under *Unreleased*) when behaviour changes.
3. Make sure the CI checks pass: **Python unit tests**, **Oracle 23ai + utPLSQL**. A pull request can only be merged with them green.
4. Pull requests are merged with *squash* (one commit per pull request) and the branch is deleted afterwards: the repository keeps only `main`.

Commit messages follow the style already in the history: a short prefix (`feat:`, `fix:`, `docs:`, `chore:`, `CI:`) and an imperative summary.

By participating you agree to follow the [code of conduct](CODE_OF_CONDUCT.md).
