#!/usr/bin/env bash
# Tests the submit-planting Edge Function, map snapshot, and anon lockdown
# against the local Supabase instance.
#
# Prerequisites (in other terminals):
#   supabase start
#   supabase db reset
#   supabase functions serve --env-file supabase/functions/.env
#
# Usage: scripts/test-local.sh
# Inserts test plantings into the local database; `supabase db reset` clears them.

set -uo pipefail

cd "$(dirname "$0")/.."

# local URL and keys from the running instance (local-only values)
eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
if [[ -z "${API_URL:-}" || -z "${ANON_KEY:-}" || -z "${SERVICE_ROLE_KEY:-}" ]]; then
  echo "Local Supabase isn't running. Run: supabase start" >&2
  exit 1
fi

FN="$API_URL/functions/v1/submit-planting"
SNAPSHOT="$API_URL/storage/v1/object/public/map-data/plantings.json"
ANON=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY")

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# smallest valid-looking JPEG and a non-image file
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9' > "$TMP/tiny.jpg"
echo "not an image" > "$TMP/note.txt"

passed=0
failed=0

# check <name> <expected status> <expected body substring or ""> <curl args...>
check() {
  local name="$1" want_status="$2" want_body="$3"
  shift 3
  local out status body
  out="$(curl -s -w $'\n%{http_code}' "$@")"
  status="${out##*$'\n'}"
  body="${out%$'\n'*}"
  if [[ "$status" == "$want_status" && ( -z "$want_body" || "$body" == *"$want_body"* ) ]]; then
    echo "  pass  $name"
    passed=$((passed + 1))
  else
    echo "  FAIL  $name"
    echo "        expected $want_status${want_body:+ containing '$want_body'}, got $status: ${body:0:200}"
    failed=$((failed + 1))
  fi
}

if ! curl -s -o /dev/null -X OPTIONS "$FN"; then
  echo "Edge Function isn't being served. Run: supabase functions serve --env-file supabase/functions/.env" >&2
  exit 1
fi

# a complete, valid submission; tests drop or replace one field at a time
FIELDS=(
  "cf-turnstile-response=test-token" # the local test secret accepts any token
  "title=Front yard strip"
  "seed_mixture=full_sun"
  "lat=40.7075"
  "lng=-74.009"
  "planted_on=2026-05-01"
  "nature_connection=5"
  "email=test@example.com"
  "photo=@$TMP/tiny.jpg;type=image/jpeg"
)

# submit <name> <status> <body substring> [drop=<field>] [<field>=<value> replacements...]
submit() {
  local name="$1" want_status="$2" want_body="$3"
  shift 3
  local drop="" replacements=()
  for arg in "$@"; do
    if [[ "$arg" == drop=* ]]; then drop="${arg#drop=}"; else replacements+=("$arg"); fi
  done
  local args=() field key replaced
  for field in "${FIELDS[@]}"; do
    key="${field%%=*}"
    [[ "$key" == "$drop" ]] && continue
    replaced=""
    for r in ${replacements[@]+"${replacements[@]}"}; do
      [[ "${r%%=*}" == "$key" ]] && replaced="$r"
    done
    args+=(-F "${replaced:-$field}")
  done
  check "$name" "$want_status" "$want_body" "${args[@]}" "$FN"
}

echo "Submissions"
submit "valid submission" 201 '"id"'
submit "valid, partial sun" 201 '"id"' "title=Back corner" "seed_mixture=partial_sun" "lat=40.711" "lng=-74.012"

echo "Rejected submissions"
submit "missing Turnstile token" 403 "Verification failed" drop=cf-turnstile-response
submit "missing title" 400 "Title" drop=title
submit "title over 100 characters" 400 "Title" "title=$(printf 'a%.0s' {1..101})"
submit "missing seed mixture" 400 "seed mixture" drop=seed_mixture
submit "unknown seed mixture" 400 "seed mixture" seed_mixture=shade
submit "missing latitude" 400 "latitude" drop=lat
submit "latitude out of range" 400 "latitude" lat=91
submit "longitude out of range" 400 "longitude" lng=181
submit "missing date" 400 "date" drop=planted_on
submit "invalid date" 400 "date" planted_on=2026-13-45
submit "missing nature_connection" 400 "nature connection" drop=nature_connection
submit "nature_connection out of range" 400 "nature connection" nature_connection=9
submit "missing email" 400 "email" drop=email
submit "invalid email" 400 "email" email=nope
submit "missing photo" 400 "Photo is required" drop=photo
submit "non-image photo" 400 "Photo must be" "photo=@$TMP/note.txt;type=text/plain"
check "GET not allowed" 405 "" "$FN"

echo "Map snapshot"
check "readable without a key" 200 '"FeatureCollection"' "$SNAPSHOT"
check "contains the submitted planting" 200 "Front yard strip" "$SNAPSHOT"

echo "Anon access is denied"
check "read public_planting_map" 401 "permission denied" "${ANON[@]}" "$API_URL/rest/v1/public_planting_map?select=*"
check "read plantings" 401 "permission denied" "${ANON[@]}" "$API_URL/rest/v1/plantings?select=*"
check "read planting_contacts" 401 "permission denied" "${ANON[@]}" "$API_URL/rest/v1/planting_contacts?select=*"
check "insert into plantings" 401 "permission denied" "${ANON[@]}" -H 'Content-Type: application/json' \
  -d '{"title":"x","seed_mixture":"full_sun","location":"POINT(1 1)"}' "$API_URL/rest/v1/plantings"
check "call submit_planting RPC" 401 "permission denied" "${ANON[@]}" -H 'Content-Type: application/json' \
  -d '{"p_title":"x","p_seed_mixture":"full_sun","p_lat":1,"p_lng":1,"p_planted_on":null,"p_nature_connection":null,"p_photo_path":null,"p_email":null}' \
  "$API_URL/rest/v1/rpc/submit_planting"
check "upload to planting-photos" 400 "row-level security" "${ANON[@]}" -H 'Content-Type: image/jpeg' \
  --data-binary "@$TMP/tiny.jpg" "$API_URL/storage/v1/object/planting-photos/test.jpg"
check "overwrite map snapshot" 400 "row-level security" "${ANON[@]}" -H 'Content-Type: application/json' \
  -H 'x-upsert: true' -d '{}' "$API_URL/storage/v1/object/map-data/plantings.json"
check "list planting-photos returns nothing" 200 "[]" "${ANON[@]}" -H 'Content-Type: application/json' \
  -d '{"prefix":""}' "$API_URL/storage/v1/object/list/planting-photos"

echo "Buckets"
# a missing file returns "Object not found" whether or not the bucket is public, so
# look up a real photo (as the service role) and request it by its public URL
PHOTO_NAME="$(curl -s -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H 'Content-Type: application/json' -d '{"prefix":"","limit":1}' \
  "$API_URL/storage/v1/object/list/planting-photos" | grep -oE '"name":"[^"]+"' | head -1 | cut -d'"' -f4)"
if [[ -z "$PHOTO_NAME" ]]; then
  echo "  FAIL  planting-photos isn't served publicly"
  echo "        no uploaded photo to test with; the valid submissions above should have added one"
  failed=$((failed + 1))
else
  check "planting-photos isn't served publicly" 400 "Bucket not found" \
    "$API_URL/storage/v1/object/public/planting-photos/$PHOTO_NAME"
fi

echo
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
