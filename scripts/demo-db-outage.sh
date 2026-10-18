#!/usr/bin/env bash
# Fault demo: Postgres goes away, then comes back.
# Hypothesis: n8n's readiness probe (/healthz/readiness checks the database)
# fails, so Kubernetes takes n8n out of the Service and requests fail fast;
# liveness (/healthz) does not depend on the database, so n8n is NOT
# restarted; when Postgres returns, n8n becomes Ready on its own and the data
# is intact because it lives on the PersistentVolume.
set -euo pipefail

NS="${NS:-echomind}"
RELEASE="${RELEASE:-echomind}"
BASE="${BASE:-http://localhost:5678}"
cd "$(dirname "$0")/.."
step() { echo; echo "== $(date +%H:%M:%S) $*"; }
memories() { kubectl -n "$NS" exec "$RELEASE-postgres-0" -- psql -U n8n -d echomind -tAc "select count(*) from memories" | tr -d '[:space:]'; }
restarts() { kubectl -n "$NS" get pods -l app.kubernetes.io/component=n8n -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'; }

step "before"
memories_before=$(memories)
restarts_before=$(restarts)
echo "memories stored: $memories_before, n8n restarts: $restarts_before"

step "fault: scale Postgres to 0"
kubectl -n "$NS" scale statefulset "$RELEASE-postgres" --replicas=0
kubectl -n "$NS" wait --for=delete pod/"$RELEASE-postgres-0" --timeout=90s || true

step "symptom: what a client sees (fast failures, no hangs)"
for _ in 1 2 3 4 5 6 7 8; do
  curl -s -o /dev/null -m 10 -w "GET /webhook/echomind-health -> %{http_code} in %{time_total}s\n" \
    "$BASE/webhook/echomind-health" || true
  sleep 3
done

step "evidence: n8n is Running but not Ready, the Service has no endpoints"
kubectl -n "$NS" get pods -l app.kubernetes.io/component=n8n \
  -o custom-columns='POD:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount'
kubectl -n "$NS" get endpointslices -l kubernetes.io/service-name="$RELEASE"

step "recover: scale Postgres back to 1"
kubectl -n "$NS" scale statefulset "$RELEASE-postgres" --replicas=1
kubectl -n "$NS" rollout status statefulset/"$RELEASE-postgres" --timeout=180s
kubectl -n "$NS" wait --for=condition=Ready pod -l app.kubernetes.io/component=n8n --timeout=300s

step "verify: the full user journey works again"
scripts/smoke.sh "$BASE"

memories_after=$(memories)
restarts_after=$(restarts)
step "verify: data survived"
echo "memories stored: before $memories_before, after $memories_after (the smoke test adds 1)"
echo "n8n restarts: before $restarts_before, after $restarts_after"

if (( memories_after >= memories_before )); then
  echo "DEMO OK: outage contained, recovered on its own, data intact"
else
  echo "DEMO FAILED: memories were lost" >&2
  exit 1
fi
