# Runbook

| SLO | Target | Measured from |
|---|---|---|
| Executions succeed | ≥ 95% of webhook executions succeed | `n8n_workflow_execution_duration_seconds_count{job="n8n"}` by `status` (error-handler and manual runs excluded; includes the health check) |
| n8n available | Ready ≥ 99% of the time | `up{job="n8n"}` (the collector's scrape) and the readiness probe |

Alert rules: `deploy/observability/grafana/echomind-alerts.yaml` (Grafana folder "echomind").

<a id="alert-echomind-high-failure-ratio"></a>
## EchoMind - more than 20% of executions failing (page)
**Symptom:** more than 20% of executions failed over 10 minutes, for 5 minutes.
**Check:**
```sh
kubectl -n echomind exec echomind-postgres-0 -- sh -c 'psql -U "$POSTGRES_USER" -d echomind -c "select occurred_at, workflow, failed_node, left(error_message,100) from workflow_errors order by id desc limit 5;"'
kubectl -n echomind logs deploy/echomind --tail=100
make history
```
**Fix:** a bad key → `make secrets` and a restart (see below); the provider is down → wait or switch `llm.baseUrl`; a bad release → `make rollback`.
**Verify:** `make smoke` passes and the ratio on the dashboard drops below 5%.

<a id="alert-echomind-n8n-down"></a>
## EchoMind - n8n not answering metrics scrapes (page)
**Symptom:** `max(up{job="n8n"}) < 1` for 2 minutes: n8n is down or not Ready.
**Check:**
```sh
kubectl -n echomind get pods
kubectl -n echomind describe pod -l app.kubernetes.io/component=n8n | tail -20
kubectl -n echomind logs deploy/echomind -c bootstrap --tail=20
```
**Fix:** Postgres not Ready → check `echomind-postgres-0`; image or config problem after a release → `make rollback`.
**Verify:** the pod is `1/1 Running`, `curl http://localhost:5678/healthz/readiness` returns `200`, and the alert resolves.

<a id="alert-echomind-error-handler-ran"></a>
## EchoMind - a webhook execution failed (from logs) (ticket)
**Symptom:** n8n logged `Webhook execution failed` in the last 10 minutes (an ingest or recall failed). It reads Loki because n8n's counters reset on restart.
**Check:** the `workflow_errors` query above, and the failed trace in Grafana → Explore → Tempo.
**Fix:** a single failure is usually an external hiccup; repeated failures trigger the failure-ratio alert.
**Verify:** no new rows in `workflow_errors` for 10 minutes.

## Procedures

**Roll back:** `make rollback` (previous revision) or `make rollback REVISION=<n>`, or run the `deploy` workflow with an older SHA. Check with `make history` and `make smoke`.

**Rotate a key:** update `.env`, then `make secrets` and `kubectl -n echomind rollout restart deploy/echomind` (credentials are imported at start-up).

**Grafana says "Plugin not registered":** `kubectl -n observability logs deploy/lgtm | grep -c 'Failed to install plugin'` should be 0; if not, `kubectl -n observability rollout restart deploy/lgtm`.

**First install:** `cp .env.example .env`, fill it in, `make up`. The first run downloads about 1.5 GB of images; if Helm's timeout expires it rolls back automatically, and the kept secrets and PVC are reused on the next `make deploy`.
