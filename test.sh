#!/bin/bash

# Lumen — API test runner
# Usage:
#   ./test.sh                        Run unauthenticated tests only
#   ./test.sh --login EMAIL PASSWORD Run full suite (logs in to get token)
#   ./test.sh --token JWT            Run full suite with a pre-existing token
#   ./test.sh --url http://host:8000 Override API base URL (default: http://localhost:8000)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

API_URL="http://localhost:8000"
AUTH_TOKEN=""
LOGIN_EMAIL=""
LOGIN_PASSWORD=""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

# ── Helpers ──────────────────────────────────────────────────────────────────

say() { echo -e "$1"; }

pass() {
  PASS=$((PASS + 1))
  say "${GREEN}  ✓ $1${NC}"
}

fail() {
  FAIL=$((FAIL + 1))
  say "${RED}  ✗ $1${NC}"
  [ -n "$2" ] && say "${RED}    → $2${NC}"
}

skip() {
  SKIP=$((SKIP + 1))
  say "${YELLOW}  – $1 (skipped — no token)${NC}"
}

section() {
  echo ""
  say "${CYAN}[ $1 ]${NC}"
}

http_get() {
  local url="$1"
  shift
  curl -s -o /tmp/lumen_test_body -w "%{http_code}" "$@" "$url"
}

http_post() {
  local url="$1"
  local body="$2"
  shift 2
  curl -s -o /tmp/lumen_test_body -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" -d "$body" "$@" "$url"
}

http_patch() {
  local url="$1"
  local body="$2"
  shift 2
  curl -s -o /tmp/lumen_test_body -w "%{http_code}" \
    -X PATCH -H "Content-Type: application/json" -d "$body" "$@" "$url"
}

http_delete() {
  local url="$1"
  shift
  curl -s -o /tmp/lumen_test_body -w "%{http_code}" -X DELETE "$@" "$url"
}

body() { cat /tmp/lumen_test_body 2>/dev/null; }

auth_header() {
  echo "Authorization: Bearer $AUTH_TOKEN"
}

expect_status() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label (HTTP $actual)"
  else
    fail "$label" "expected HTTP $expected, got HTTP $actual — $(body | head -c 200)"
  fi
}

extract_json() {
  local key="$1"
  body | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('$key',''))" 2>/dev/null || true
}

# ── Argument parsing ──────────────────────────────────────────────────────────

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --url)
        API_URL="$2"; shift 2 ;;
      --token)
        AUTH_TOKEN="$2"; shift 2 ;;
      --login)
        LOGIN_EMAIL="$2"
        LOGIN_PASSWORD="$3"
        shift 3 ;;
      --help|-h)
        head -6 "$0" | grep "^#" | sed 's/^# //'
        exit 0 ;;
      *)
        say "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
  done
}

# ── Test suites ───────────────────────────────────────────────────────────────

test_unauthenticated() {
  section "Unauthenticated endpoints"

  local status
  status=$(http_get "$API_URL/health")
  if [ "$status" = "200" ]; then
    local db_status
    db_status=$(extract_json "status")
    pass "GET /health (HTTP 200, status=$db_status)"
  else
    fail "GET /health" "expected 200, got $status"
  fi

  status=$(http_get "$API_URL/docs")
  expect_status "GET /docs (Swagger UI)" "200" "$status"

  status=$(http_get "$API_URL/openapi.json")
  expect_status "GET /openapi.json" "200" "$status"

  # Auth-required endpoints should return 403 or 401, not 200 or 500
  status=$(http_get "$API_URL/entries")
  if [ "$status" = "401" ] || [ "$status" = "403" ]; then
    pass "GET /entries without token → $status (auth required)"
  else
    fail "GET /entries without token" "expected 401/403, got $status"
  fi

  status=$(http_get "$API_URL/users/me")
  if [ "$status" = "401" ] || [ "$status" = "403" ]; then
    pass "GET /users/me without token → $status (auth required)"
  else
    fail "GET /users/me without token" "expected 401/403, got $status"
  fi
}

test_login() {
  section "Login"

  local status
  status=$(http_post "$API_URL/auth/login" \
    "{\"email\": \"$LOGIN_EMAIL\", \"password\": \"$LOGIN_PASSWORD\"}")

  if [ "$status" = "200" ]; then
    AUTH_TOKEN=$(body | python3 -c "
import sys, json
d = json.load(sys.stdin)
# Supabase proxied response nests under session or top-level
token = (d.get('access_token') or
         d.get('token') or
         (d.get('session') or {}).get('access_token') or '')
print(token)
" 2>/dev/null || true)

    if [ -n "$AUTH_TOKEN" ]; then
      pass "POST /auth/login — token obtained"
    else
      fail "POST /auth/login" "HTTP 200 but no access_token in response: $(body | head -c 300)"
      AUTH_TOKEN=""
    fi
  else
    fail "POST /auth/login" "HTTP $status — $(body | head -c 200)"
  fi
}

test_me() {
  section "Current user"

  if [ -z "$AUTH_TOKEN" ]; then skip "GET /users/me"; return; fi

  local status
  status=$(http_get "$API_URL/users/me" -H "$(auth_header)")
  expect_status "GET /users/me" "200" "$status"

  if [ "$status" = "200" ]; then
    local user_id
    user_id=$(extract_json "id")
    if [ -n "$user_id" ]; then
      pass "  id field present: $user_id"
    else
      fail "  id field missing from /users/me response"
    fi
  fi
}

test_entries_crud() {
  section "Entries CRUD"

  if [ -z "$AUTH_TOKEN" ]; then
    skip "POST /entries"
    skip "GET /entries"
    skip "GET /entries/{id}"
    skip "PATCH /entries/{id}"
    skip "DELETE /entries/{id}"
    return
  fi

  # Create
  local create_body='{
    "title": "Test Entry",
    "body": "Created by test.sh",
    "tags": ["test"],
    "theme": "neutral",
    "accentColor": {"bg": "#fff"},
    "favorite": false,
    "pinned": false,
    "collection": "",
    "checklist": [],
    "templateId": "",
    "promptId": "",
    "relatedEntryIds": []
  }'
  local status
  status=$(http_post "$API_URL/entries" "$create_body" -H "$(auth_header)")
  expect_status "POST /entries" "201" "$status"
  local entry_id
  entry_id=$(extract_json "id")

  if [ -z "$entry_id" ]; then
    fail "  id not returned from POST /entries"
    skip "GET /entries/{id}"
    skip "PATCH /entries/{id}"
    skip "DELETE /entries/{id}"
    return
  fi
  pass "  entry id: $entry_id"

  # List
  status=$(http_get "$API_URL/entries" -H "$(auth_header)")
  expect_status "GET /entries" "200" "$status"

  # Get by id
  status=$(http_get "$API_URL/entries/$entry_id" -H "$(auth_header)")
  expect_status "GET /entries/$entry_id" "200" "$status"

  # Get non-existent → 404
  status=$(http_get "$API_URL/entries/nonexistent-id-000" -H "$(auth_header)")
  expect_status "GET /entries/nonexistent-id → 404" "404" "$status"

  # Update
  status=$(http_patch "$API_URL/entries/$entry_id" \
    '{"title": "Updated by test.sh"}' -H "$(auth_header)")
  expect_status "PATCH /entries/$entry_id" "200" "$status"

  # Delete
  status=$(http_delete "$API_URL/entries/$entry_id" -H "$(auth_header)")
  expect_status "DELETE /entries/$entry_id" "204" "$status"

  # Confirm gone
  status=$(http_get "$API_URL/entries/$entry_id" -H "$(auth_header)")
  expect_status "GET deleted entry → 404" "404" "$status"
}

test_auth_edge_cases() {
  section "Auth edge cases"

  local status

  # Malformed token
  status=$(http_get "$API_URL/entries" -H "Authorization: Bearer not-a-real-token")
  if [ "$status" = "401" ] || [ "$status" = "403" ]; then
    pass "Malformed token → $status"
  else
    fail "Malformed token" "expected 401/403, got $status"
  fi

  # No authorization header at all (entries)
  status=$(http_get "$API_URL/entries")
  if [ "$status" = "401" ] || [ "$status" = "403" ]; then
    pass "Missing auth header → $status"
  else
    fail "Missing auth header" "expected 401/403, got $status"
  fi
}

test_logout() {
  section "Logout"

  if [ -z "$AUTH_TOKEN" ]; then skip "POST /auth/logout"; return; fi

  local status
  status=$(http_post "$API_URL/auth/logout" '{}' -H "$(auth_header)")
  if [ "$status" = "200" ] || [ "$status" = "204" ]; then
    pass "POST /auth/logout (HTTP $status)"
  else
    fail "POST /auth/logout" "expected 200/204, got $status"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"

  say "${GREEN}Lumen — API Test Runner${NC}"
  say "  Target: $API_URL"
  if [ -n "$AUTH_TOKEN" ]; then
    say "  Auth:   token provided"
  elif [ -n "$LOGIN_EMAIL" ]; then
    say "  Auth:   will login as $LOGIN_EMAIL"
  else
    say "${YELLOW}  Auth:   none — authenticated tests will be skipped${NC}"
  fi

  if ! command -v curl > /dev/null 2>&1; then
    say "${RED}ERROR: curl is required.${NC}"; exit 1
  fi
  if ! command -v python3 > /dev/null 2>&1; then
    say "${RED}ERROR: python3 is required for JSON parsing.${NC}"; exit 1
  fi

  test_unauthenticated
  test_auth_edge_cases

  if [ -z "$AUTH_TOKEN" ] && [ -n "$LOGIN_EMAIL" ]; then
    test_login
  fi

  test_me
  test_entries_crud
  test_logout

  echo ""
  say "${CYAN}────────────────────────────────${NC}"
  say "${GREEN}  Passed: $PASS${NC}"
  if [ "$FAIL" -gt 0 ]; then
    say "${RED}  Failed: $FAIL${NC}"
  else
    say "  Failed: $FAIL"
  fi
  if [ "$SKIP" -gt 0 ]; then
    say "${YELLOW}  Skipped: $SKIP${NC}"
  fi
  echo ""

  [ "$FAIL" -eq 0 ]
}

main "$@"
