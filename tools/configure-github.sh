#!/usr/bin/env bash
# Configures this repository on GitHub with the platform's recommended practices.
# Safe to run again: every step creates or updates what is already there.
#
# Usage (from the project folder, with gh signed in as the repository owner):
#   bash tools/configure-github.sh
set -euo pipefail

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
try() {
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$what"; else printf '  \033[33m!\033[0m %s: could not enable it here (check Settings > Code security)\n' "$what"; fi
}
DESCRIPTION="Open-source airline punctuality analytics on Oracle AI Database 26ai, PL/SQL and utPLSQL, with Brazil's official ANAC flight data"
TOPICS="oracle,plsql,utplsql,oracle-database,data-engineering,star-schema,aviation,on-time-performance,anac,open-data,python,docker"
echo "Repository: $REPO"

step "1. Presentation"
gh repo edit "$REPO" --description "$DESCRIPTION" --add-topic "$TOPICS" --enable-wiki=false --enable-projects=false >/dev/null
ok "description and topics; Wiki and Projects off (documentation lives in docs/)"

step "2. Pull requests"
gh repo edit "$REPO" --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false \
  --delete-branch-on-merge --enable-auto-merge --allow-update-branch >/dev/null
ok "squash only (linear history), branch deleted on merge, auto-merge allowed"

step "3. Security"
try "Dependabot alerts" gh api -X PUT "repos/$REPO/vulnerability-alerts"
try "Dependabot security updates" gh api -X PUT "repos/$REPO/automated-security-fixes"
try "private vulnerability reporting (SECURITY.md)" gh api -X PUT "repos/$REPO/private-vulnerability-reporting"
try "secret scanning" gh api -X PATCH "repos/$REPO" -f "security_and_analysis[secret_scanning][status]=enabled"
try "push protection for secrets" gh api -X PATCH "repos/$REPO" -f "security_and_analysis[secret_scanning_push_protection][status]=enabled"
try "CodeQL code scanning" gh api -X PATCH "repos/$REPO/code-scanning/default-setup" -f state=configured -f query_suite=default

step "4. GitHub Actions"
gh api -X PUT "repos/$REPO/actions/permissions/workflow" -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null
ok "read-only token by default (each workflow asks for what it needs)"

step "5. Rulesets"
ruleset() {
  local name="$1" json="$2" id
  id="$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id")"
  if [[ -n "$id" ]]; then gh api -X PUT "repos/$REPO/rulesets/$id" --input - <<<"$json" >/dev/null
  else gh api -X POST "repos/$REPO/rulesets" --input - <<<"$json" >/dev/null; fi
}
# The admin (you) can still push straight to main; everyone else, Dependabot included,
# goes through a pull request with the checks green.
ruleset "Protect main" '{
  "name": "Protect main", "target": "branch", "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}],
  "rules": [
    {"type": "deletion"}, {"type": "non_fast_forward"}, {"type": "required_linear_history"},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": false,
      "required_status_checks": [
        {"context": "Python unit tests", "integration_id": 15368},
        {"context": "Oracle 23ai + utPLSQL", "integration_id": 15368}]}}
  ]}'
ok "main: no deletion, no force push, linear history; pull requests need Python unit tests and Oracle 23ai + utPLSQL"
ruleset "Protect releases" '{
  "name": "Protect releases", "target": "tag", "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
  "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}],
  "rules": [{"type": "deletion"}, {"type": "update"}]}'
ok "v* tags: only the admin can delete or move them"

step "6. Labels"
gh label create bug --color B42318 --description "Something fails or gives a wrong result" --force >/dev/null
gh label create enhancement --color 0E6B5A --description "Idea or improvement" --force >/dev/null
gh label create dependencies --color 6B7280 --description "Automatic update (Dependabot)" --force >/dev/null
ok "bug, enhancement and dependencies"

step "7. Branches other than main"
mapfile -t branches < <(gh api "repos/$REPO/branches" --paginate --jq '.[].name' | grep -vx main || true)
if ((${#branches[@]} == 0)); then ok "only main exists"; else
  for b in "${branches[@]}"; do
    pr="$(gh pr list --head "$b" --state open --json number --jq '.[0].number')"
    if [[ -n "$pr" ]]; then gh pr close "$pr" --delete-branch >/dev/null; else gh api -X DELETE "repos/$REPO/git/refs/heads/$b" >/dev/null; fi
    ok "removed: $b"
  done
fi

echo
echo "Done. One manual step left: Settings > General > Social preview > Edit > Upload,"
echo "with docs/images/social-preview.png."
