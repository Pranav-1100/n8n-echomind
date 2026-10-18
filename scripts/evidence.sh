#!/usr/bin/env bash
# Captures verification evidence for the version running in the local cluster:
# source -> pipeline -> release -> runtime -> user journey -> security -> telemetry.
# Output: docs/evidence/<running-sha>.md. Safe to re-run: it only reads state,
# except the smoke test, which stores one test memory. No secret values are
# written.
set -uo pipefail

NS="${NS:-echomind}"
RELEASE="${RELEASE:-echomind}"
BASE="${BASE:-http://localhost:5678}"
GRAFANA="${GRAFANA:-http://localhost:3300}"
GRAFANA_AUTH="${GRAFANA_AUTH:-admin:admin}"
REPO="${REPO:-Pranav-1100/n8n-echomind}"
BASELINE=423c114d6dbcbd34af931eeec994c0600eead501
cd "$(dirname "$0")/.."

image=$(kubectl -n "$NS" get deploy "$RELEASE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
[[ -n "$image" ]] || { echo "deployment $RELEASE not found in namespace $NS" >&2; exit 1; }
running="${image##*:}"
commit="${running%-dirty}"
# A local dev build may use a tag that is not a commit; then fall back to the
# version the image itself reports at start-up, and finally to HEAD.
if ! git cat-file -e "${commit}^{commit}" 2>/dev/null; then
  reported=$(kubectl -n "$NS" logs deploy/"$RELEASE" -c bootstrap 2>/dev/null |
    sed -nE 's/.*bootstrap complete: version ([^,]+),.*/\1/p' | tail -1)
  commit="${reported%-dirty}"
  git cat-file -e "${commit}^{commit}" 2>/dev/null || commit=$(git rev-parse HEAD)
fi
mkdir -p docs/evidence
out="docs/evidence/${running}.md"

section() { printf '\n## %s\n\n' "$1"; }
run() { printf '```console\n$ %s\n' "$*"; eval "$@" 2>&1; printf '```\n'; }
# Prometheus and Tempo are queried through the Kubernetes API service proxy, so
# no port-forward is needed.
urlencode() { node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$1"; }
promql() {
  kubectl get --raw "/api/v1/namespaces/observability/services/lgtm:9090/proxy/api/v1/query?query=$(urlencode "$1")" 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=JSON.parse(s).data.result;
      if(!r.length){console.log("(no data)");return}
      for(const x of r){const m={...x.metric};delete m.__name__;console.log(JSON.stringify(m),"=>",x.value[1])}})' 2>&1 ||
    echo "(query failed)"
}
psql_count() {
  kubectl -n "$NS" exec "$RELEASE-postgres-0" -- psql -U n8n -d echomind -tAc "select count(*) from $1" 2>/dev/null || echo "(n/a)"
}

{
  echo "# Evidence for \`${running}\`"
  echo
  echo "Captured $(date -u +%Y-%m-%dT%H:%M:%SZ) by \`scripts/evidence.sh\` against the local kind cluster."
  [[ "$running" == *-dirty ]] && echo && echo "> Built from a working tree with uncommitted changes on top of \`${commit}\`."

  section "1. Source"
  run "git log -1 --format='commit %H%nauthor %an%ndate   %ad%n%n    %s' ${commit}"
  echo "Baseline: \`${BASELINE}\`"
  echo
  run "git log --oneline ${BASELINE}..${commit}"

  section "2. Pipeline runs for this commit"
  if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    run "gh run list -R ${REPO} --commit ${commit} --json workflowName,event,status,conclusion,url --template '{{range .}}{{.workflowName}} ({{.event}}): {{.status}}/{{.conclusion}} {{.url}}{{\"\\n\"}}{{end}}'"
  else
    echo "gh CLI not authenticated; see the Actions tab for commit ${commit}."
  fi

  section "3. Release (Helm)"
  run "helm history ${RELEASE} -n ${NS} --max 6"
  run "helm get values ${RELEASE} -n ${NS}"

  section "4. Runtime (Kubernetes)"
  run "kubectl get nodes -o wide"
  run "kubectl -n ${NS} get deploy,statefulset,pods,svc,pvc,networkpolicy -o wide"
  run "kubectl -n ${NS} get pods -o custom-columns='POD:.metadata.name,IMAGE:.spec.containers[0].image,IMAGE_ID:.status.containerStatuses[0].imageID,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount'"
  run "kubectl get namespace ${NS} --show-labels"
  echo "Start-up (init container \`bootstrap\`):"
  echo
  run "kubectl -n ${NS} logs deploy/${RELEASE} -c bootstrap | grep -E 'reachable|Successfully imported|Publishing|bootstrap complete' | sed -E 's/.*\"message\":\"([^\"]*)\".*/\\1/'"

  section "5. Running version matches the commit"
  run "kubectl -n ${NS} get deploy ${RELEASE} -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}'"
  run "kubectl -n ${NS} get pods -l app.kubernetes.io/component=n8n -o jsonpath='{.items[0].metadata.labels.app\\.kubernetes\\.io/version}{\"\\n\"}'"

  section "6. User journey (health -> auth -> validation -> ingest -> recall)"
  run "scripts/smoke.sh ${BASE} ${running}"
  run "helm test ${RELEASE} -n ${NS} --logs | tail -6"
  echo "Rows in the application database:"
  echo
  echo '```'
  for t in memories memory_vectors workflow_errors; do echo "$t: $(psql_count "$t")"; done
  echo '```'

  section "7. Security controls"
  run "scripts/netpol-check.sh ${NS} ${RELEASE}"
  run "kubectl auth can-i --list -n ${NS} --as=system:serviceaccount:${NS}:${RELEASE} | head -8"
  run "kubectl -n ${NS} get pods -o jsonpath='{range .items[*]}{.metadata.name}{\"\\n  pod: \"}{.spec.securityContext}{\"\\n  container: \"}{.spec.containers[0].securityContext}{\"\\n\"}{end}'"
  run "scripts/drift.sh ${NS} ${RELEASE}"

  section "8. Telemetry (Prometheus, Tempo, Loki and Grafana alert rules)"
  echo "Running n8n version and scrape health:"
  echo '```'; promql 'count by (version) (n8n_version_info{job="n8n"})'; promql 'up{job="n8n"}'; echo '```'
  echo "Execution success ratio, last 30m (SLO >= 95%; error-handler and manual runs excluded):"
  echo '```'; promql 'sum(increase(n8n_workflow_execution_duration_seconds_count{job="n8n",status="success",mode!~"error|manual"}[30m])) / sum(increase(n8n_workflow_execution_duration_seconds_count{job="n8n",mode!~"error|manual"}[30m]))'; echo '```'
  echo "Executions by status and mode, last 30m:"
  echo '```'; promql 'sum by (status, mode) (increase(n8n_workflow_execution_duration_seconds_count{job="n8n"}[30m]))'; echo '```'
  echo "Execution duration p95 in seconds by mode, last 30m:"
  echo '```'; promql 'histogram_quantile(0.95, sum by (le, mode) (rate(n8n_workflow_execution_duration_seconds_bucket{job="n8n"}[30m])))'; echo '```'
  echo "Recent traces (Tempo):"
  echo '```'
  kubectl get --raw '/api/v1/namespaces/observability/services/lgtm:3200/proxy/api/search?limit=5' 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s).traces||[];if(!t.length)console.log("(no traces)");for(const x of t)console.log(x.traceID,x.rootServiceName,"|",x.rootTraceName,"|",(x.durationMs||0)+"ms")})' 2>&1 ||
    echo "(query failed)"
  echo '```'
  echo "Recent n8n log lines (Loki, service_name=echomind):"
  echo '```'
  kubectl -n observability exec deploy/lgtm -- curl -s -G localhost:3100/loki/api/v1/query_range \
    --data-urlencode 'query={service_name="echomind"}' --data-urlencode 'limit=3' 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=(JSON.parse(s).data||{}).result||[];const v=r.flatMap(x=>x.values);if(!v.length)console.log("(no log lines)");for(const [,l] of v.slice(0,3))console.log(l.slice(0,200))})' 2>&1 ||
    echo "(query failed)"
  echo '```'
  echo "Alert rules loaded in Grafana:"
  echo '```'
  curl -fsS -m 20 -u "$GRAFANA_AUTH" "$GRAFANA/api/v1/provisioning/alert-rules" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{for(const r of JSON.parse(s))console.log("-",r.title)})' 2>&1 ||
    echo "(query failed)"
  echo '```'
} > "$out"

echo "Evidence written to $out"
