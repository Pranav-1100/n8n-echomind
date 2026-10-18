#!/usr/bin/env bash
# Fault demo: the LLM provider rejects our key (as if it were revoked or the
# provider were down).
# Hypothesis: n8n itself stays healthy (the platform is fine), the ingest
# request fails with 500 instead of a false "stored", the error-logger
# workflow records the failure in Postgres, and the failed-executions metric
# rises (the alert's signal). Restoring the key restores the journey.
# The original key is kept in a shell variable only and is ALWAYS restored,
# even if the script is interrupted.
set -euo pipefail

NS="${NS:-echomind}"
RELEASE="${RELEASE:-echomind}"
BASE="${BASE:-http://localhost:5678}"
INGEST="$BASE/webhook/b3f32965-eaf7-4301-82ca-1945d8ff2de5"
cd "$(dirname "$0")/.."
step() { echo; echo "== $(date +%H:%M:%S) $*"; }
sql() { kubectl -n "$NS" exec "$RELEASE-postgres-0" -- psql -U n8n -d echomind -tAc "$1"; }
failed_executions() {
  local q
  q=$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' 'sum(n8n_workflow_execution_duration_seconds_count{job="n8n",status="failed"})')
  kubectl get --raw "/api/v1/namespaces/observability/services/lgtm:9090/proxy/api/v1/query?query=$q" 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=JSON.parse(s).data.result;console.log(r.length?r[0].value[1]:"0")})' 2>/dev/null ||
    echo "n/a"
}
restart_n8n() {
  kubectl -n "$NS" rollout restart deploy/"$RELEASE" >/dev/null
  kubectl -n "$NS" rollout status deploy/"$RELEASE" --timeout=5m
}
patch_llm_key() {
  # $1 = base64 value; passed through a private temp file, never on the command line
  local patch
  patch=$(mktemp)
  chmod 600 "$patch"
  printf '{"data":{"LLM_API_KEY":"%s"}}' "$1" > "$patch"
  kubectl -n "$NS" patch secret echomind-api-keys --type merge --patch-file "$patch" >/dev/null
  rm -f "$patch"
}

original_b64=$(kubectl -n "$NS" get secret echomind-api-keys -o jsonpath='{.data.LLM_API_KEY}')
[[ -n "$original_b64" ]] || { echo "LLM_API_KEY not found in secret echomind-api-keys" >&2; exit 1; }
restored=false
restore() {
  if ! $restored; then
    step "restore: put the original LLM key back and restart n8n"
    patch_llm_key "$original_b64"
    restart_n8n
    restored=true
  fi
}
trap restore EXIT

token=$(kubectl -n "$NS" get secret echomind-api-keys -o jsonpath='{.data.ECHOMIND_INGEST_TOKEN}' | base64 --decode)

step "before"
errors_before=$(sql "select count(*) from workflow_errors" | tr -d '[:space:]')
failed_before=$(failed_executions)
echo "workflow_errors rows: $errors_before, failed executions (metric): $failed_before"

step "fault: replace the LLM key with an invalid one and restart n8n (credentials load at start-up)"
patch_llm_key "$(printf 'invalid-key-for-demo' | base64)"
restart_n8n

step "symptom: ingest fails honestly (500), n8n itself stays healthy"
code=$(printf 'header = "X-EchoMind-Token: %s"\n' "$token" | curl -K - -s -o /dev/null -m 120 -w '%{http_code}' \
  -X POST "$INGEST" -H 'content-type: application/json' \
  -d '{"speaker":"demo","transcript":"This memory cannot be processed while the LLM key is invalid."}')
echo "POST ingest -> $code (500 expected)"
curl -s -o /dev/null -m 10 -w "GET /healthz -> %{http_code}\n" "$BASE/healthz"

step "evidence: the error logger recorded it in Postgres"
for _ in $(seq 1 10); do
  errors_after=$(sql "select count(*) from workflow_errors" | tr -d '[:space:]')
  (( errors_after > errors_before )) && break
  sleep 2
done
echo "workflow_errors rows: before $errors_before, after $errors_after"
sql "select occurred_at, workflow, failed_node, left(error_message, 80) from workflow_errors order by id desc limit 1"

step "evidence: failed-executions metric (scraped every 15s)"
sleep 30
echo "failed executions: before $failed_before, now $(failed_executions)"

restore
trap - EXIT

step "verify: the full user journey works again"
scripts/smoke.sh "$BASE"

if [[ "$code" == 500 ]] && (( errors_after > errors_before )); then
  echo "DEMO OK: failure surfaced as 500, logged, measured; recovered after restoring the key"
else
  echo "DEMO FAILED: expected a 500 and a new workflow_errors row" >&2
  exit 1
fi
