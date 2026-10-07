#!/usr/bin/env bash
# Deploys the submit-planting Edge Function to the hosted Supabase project, then
# checks that the deployed function responds.
#
# Usage:
#   scripts/deploy-function.sh             # check, deploy, smoke-test
#   scripts/deploy-function.sh --dry-run   # checks only, no deploy
#
# Requires `supabase login`. Deploys only to PROJECT_REF below, regardless of
# which project is linked.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT_REF="iiimikqpfwvktlmvfvtj" # SprinklingSeeds
FUNCTION="submit-planting"
FN_URL="https://$PROJECT_REF.supabase.co/functions/v1/$FUNCTION"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

step() { echo; echo "==> $*"; }
die() { echo "error: $*" >&2; exit 1; }

step "Type-checking the function"
if command -v deno >/dev/null; then
  (cd "supabase/functions/$FUNCTION" && deno check index.ts) || die "type check failed"
else
  echo "deno not installed; skipping type check"
fi

step "Checking secrets on $PROJECT_REF"
secrets="$(supabase secrets list --project-ref "$PROJECT_REF" -o json 2>&1)" ||
  die "couldn't list secrets (run \`supabase login\`?): $secrets"
grep -q '"TURNSTILE_SECRET"' <<<"$secrets" ||
  die "TURNSTILE_SECRET isn't set; every submission would fail. Run: supabase secrets set --project-ref $PROJECT_REF TURNSTILE_SECRET=<secret>"
echo "TURNSTILE_SECRET is set"

if $DRY_RUN; then
  echo; echo "Dry run: checks passed, nothing deployed."
  exit 0
fi

step "Deploying $FUNCTION"
supabase functions deploy "$FUNCTION" --project-ref "$PROJECT_REF"

step "Smoke-testing $FN_URL"
# GET with no key: reaching the function's own 405 shows it's deployed and needs no API key
out="$(curl -s -w $'\n%{http_code}' "$FN_URL")"
[[ "${out##*$'\n'}" == "405" && "$out" == *"Method not allowed"* ]] ||
  die "expected 405 from the function, got: ${out//$'\n'/ }"
echo "reachable without an API key"

# POST with no Turnstile token: should be rejected before anything is written
out="$(curl -s -w $'\n%{http_code}' -F title=deploy-check "$FN_URL")"
[[ "${out##*$'\n'}" == "403" ]] ||
  die "expected 403 for a submission without a Turnstile token, got: ${out//$'\n'/ }"
echo "rejects submissions without a Turnstile token"

echo; echo "Deployed. Logs: https://supabase.com/dashboard/project/$PROJECT_REF/functions/$FUNCTION/logs"
