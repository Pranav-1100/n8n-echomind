#!/usr/bin/env bash
# Fault demo: a release whose pod can never start (an image tag that does not
# exist, as if the wrong SHA were promoted).
# Hypothesis: Helm's --rollback-on-failure restores the previous revision when
# the rollout times out, and the running image is the original one again.
# Because n8n uses the Recreate strategy (one main process at a time), the old
# pod is stopped before the new one starts, so there IS downtime: the script
# measures it instead of hiding it.
set -euo pipefail

NS="${NS:-echomind}"
RELEASE="${RELEASE:-echomind}"
BASE="${BASE:-http://localhost:5678}"
BAD_TAG="${BAD_TAG:-0000000000000000000000000000000000000bad}"
cd "$(dirname "$0")/.."
step() { echo; echo "== $(date +%H:%M:%S) $*"; }

image_before=$(kubectl -n "$NS" get deploy "$RELEASE" -o jsonpath='{.spec.template.spec.containers[0].image}')
revision_before=$(helm status "$RELEASE" -n "$NS" -o json | sed -E 's/.*"version":([0-9]+).*/\1/')
step "before: revision $revision_before, image $image_before"

step "probe the health workflow every second while the bad release rolls out"
probe_log=$(mktemp)
( while true; do
    code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$BASE/webhook/echomind-health" || true)
    echo "$(date +%s) ${code:-000}" >> "$probe_log" 2>/dev/null || true
    sleep 1
  done ) &
prober=$!

step "deploy bad release ($BAD_TAG) with --rollback-on-failure"
set +e
helm upgrade "$RELEASE" charts/echomind -n "$NS" --reuse-values --set image.tag="$BAD_TAG" \
  --rollback-on-failure --wait --timeout 90s --description "demo: bad release ($BAD_TAG)"
helm_exit=$?
set -e
echo "helm exit code: $helm_exit (non-zero expected)"

step "wait for the restored revision to become ready"
kubectl -n "$NS" rollout status deploy/"$RELEASE" --timeout=5m
for _ in $(seq 1 60); do
  [[ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$BASE/webhook/echomind-health" || true)" == 200 ]] && break
  sleep 2
done

# Stop the prober explicitly; a file-based stop flag races with its own writes.
kill "$prober" 2>/dev/null || true
wait "$prober" 2>/dev/null || true
cp "$probe_log" "$probe_log.done"
rm -f "$probe_log"
total=$(wc -l < "$probe_log.done" | tr -d ' ')
failed=$(grep -vc ' 200$' "$probe_log.done" || true)
rm -f "$probe_log.done"

step "evidence: release history"
helm history "$RELEASE" -n "$NS" --max 4

image_after=$(kubectl -n "$NS" get deploy "$RELEASE" -o jsonpath='{.spec.template.spec.containers[0].image}')
step "after: image $image_after"
echo "health probes: $total sent, $failed failed (~${failed}s of downtime: Recreate stops the old pod first)"

if [[ "$image_after" == "$image_before" && "$helm_exit" != 0 ]]; then
  echo "DEMO OK: the bad release was rolled back automatically; the original image is running again"
else
  echo "DEMO FAILED: expected a failed upgrade and the original image back" >&2
  exit 1
fi
