#!/usr/bin/env bash
# Checks a deployed EchoMind end to end.
#   scripts/smoke.sh <base-url> [expected-sha]
# SMOKE_MODE=ci   platform checks only: health workflow, running version, auth
#                 and input validation. No external AI calls, so it works in CI
#                 with dummy keys.
# default (full)  also runs the real user journey: ingest a memory, recall it.
# Tokens are read from the cluster Secret into shell variables and passed to
# curl through stdin, so they never show up in output or process lists.
set -euo pipefail

BASE="${1:-http://localhost:5678}"
EXPECTED_SHA="${2:-}"
NS="${NS:-echomind}"
MODE="${SMOKE_MODE:-full}"
INGEST="$BASE/webhook/b3f32965-eaf7-4301-82ca-1945d8ff2de5"
RECALL="$BASE/webhook/9216b954-b7b0-44b2-b57a-bfd45c8940ea/chat"

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
secret() { kubectl -n "$NS" get secret echomind-api-keys -o jsonpath="{.data.$1}" | base64 --decode; }
# curl with an extra config line (header or user) read from stdin
curl_with() { local config=$1; shift; printf '%s\n' "$config" | curl -K - "$@"; }

echo "== health workflow ($MODE mode)"
health=""
for _ in $(seq 1 40); do
  health=$(curl -fsS -m 10 "$BASE/webhook/echomind-health" 2>/dev/null) && break
  sleep 3
done
echo "$health"
[[ "$health" == *'"status":"ok"'* ]] || fail "health workflow did not answer ok"

if [[ -n "$EXPECTED_SHA" ]]; then
  echo "== running version"
  image=$(kubectl -n "$NS" get deploy echomind -o jsonpath='{.spec.template.spec.containers[0].image}')
  echo "$image"
  [[ "${image##*:}" == "$EXPECTED_SHA" ]] || fail "running image tag ${image##*:} does not match expected $EXPECTED_SHA"
fi

TOKEN=$(secret ECHOMIND_INGEST_TOKEN)
PASSWORD=$(secret ECHOMIND_RECALL_PASSWORD)
[[ -n "$TOKEN" && -n "$PASSWORD" ]] || fail "could not read tokens from secret echomind-api-keys in namespace $NS"

echo "== ingest without token -> 403"
code=$(curl -s -o /dev/null -m 30 -w '%{http_code}' -X POST "$INGEST" \
  -H 'content-type: application/json' -d '{"transcript":"smoke"}')
echo "$code"
[[ "$code" == 403 ]] || fail "expected 403 without token, got $code"

echo "== ingest without transcript -> 400"
code=$(curl_with "header = \"X-EchoMind-Token: $TOKEN\"" -s -o /dev/null -m 30 -w '%{http_code}' \
  -X POST "$INGEST" -H 'content-type: application/json' -d '{"speaker":"smoke-test"}')
echo "$code"
[[ "$code" == 400 ]] || fail "expected 400 without transcript, got $code"

echo "== recall without login -> 401"
code=$(curl -s -o /dev/null -m 30 -w '%{http_code}' -X POST "$RECALL" \
  -H 'content-type: application/json' -d '{"action":"sendMessage","sessionId":"smoke","chatInput":"hi"}')
echo "$code"
[[ "$code" == 401 ]] || fail "expected 401 without login, got $code"

if [[ "$MODE" == ci ]]; then
  echo "SMOKE OK (ci): health, version, auth and validation on $BASE"
  exit 0
fi

marker="release-$(date +%s)-$RANDOM"
echo "== ingest a memory -> 201 (real LLM + embeddings, can take ~15s)"
resp=$(curl_with "header = \"X-EchoMind-Token: $TOKEN\"" -s -m 120 -w '\n%{http_code}' -X POST "$INGEST" \
  -H 'content-type: application/json' \
  -d "{\"speaker\":\"smoke-test\",\"transcript\":\"In the smoke test call we agreed that checklist $marker is owned by the platform team and is due on Friday.\"}")
code=${resp##*$'\n'}
body=${resp%$'\n'*}
echo "$body"
[[ "$code" == 201 && "$body" == *'"status":"stored"'* ]] || fail "ingest returned $code"

echo "== recall it -> 200"
resp=$(curl_with "user = \"echomind:$PASSWORD\"" -s -m 120 -w '\n%{http_code}' -X POST "$RECALL" \
  -H 'content-type: application/json' \
  -d "{\"action\":\"sendMessage\",\"sessionId\":\"smoke-$marker\",\"chatInput\":\"Who owns checklist $marker and when is it due?\"}")
code=${resp##*$'\n'}
body=${resp%$'\n'*}
echo "$body"
[[ "$code" == 200 && "$body" == *'"text":"'?* ]] || fail "recall returned $code"
[[ "$body" != *'"text":""'* ]] || fail "recall returned an empty answer"

echo "SMOKE OK (full): health, version, auth, validation, ingest and recall on $BASE"
