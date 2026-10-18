# Runbook

## What "healthy" means

| SLO | Target | Measured from |
|---|---|---|
| Executions succeed | ≥ 95% of production executions (ingest, recall) succeed | `n8n_workflow_execution_duration_seconds_count{job="n8n"}` by `status` (`success` / `failed`); error-handler runs (`mode="error"`) and manual runs are excluded |
| n8n available | n8n ready ≥ 99% of the time | The collector's scrape of n8n `/metrics` (`up{job="n8n"}`), and the readiness probe |

95% rather than 99% because each ingest makes three LLM calls and one embedding call to external services, and those services are the weakest link.

The alert rules live in `deploy/observability/grafana/echomind-alerts.yaml` (Grafana folder "echomind"). Their expressions, for use in Grafana → Explore → Prometheus:

```promql
# EchoMind - more than 20% of executions failing (fires above 0.2 for 5m)
sum(increase(n8n_workflow_execution_duration_seconds_count{job="n8n",status="failed",mode!~"error|manual"}[10m]))
/
sum(increase(n8n_workflow_execution_duration_seconds_count{job="n8n",mode!~"error|manual"}[10m]))

# EchoMind - n8n not answering metrics scrapes (fires below 1 for 2m)
max(up{job="n8n"})

# EchoMind - error logger workflow ran (fires above 0 immediately)
sum(increase(n8n_workflow_execution_duration_seconds_count{job="n8n",mode="error"}[10m]))
```

Quick health check from the laptop:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:5678/healthz/readiness   # 200 = ready
curl -s http://localhost:5678/webhook/echomind-health                             # {"status":"ok",...}
make smoke                                                                        # full user journey
```

---

<a id="alert-echomind-high-failure-ratio"></a>
## Alert: EchoMind - more than 20% of executions failing (page)

**Fires when:** over the last 10 minutes, more than 20% of production executions failed, and that stays true for 5 minutes.

**Likely causes:** the LLM endpoint is down, out of credits or rate-limited; Hugging Face is down; a bad workflow change was released; an expired or wrong API key.

**Checks:**

```sh
# 1. Which workflow and node fail, and why
kubectl -n echomind exec echomind-postgres-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d echomind -c "select occurred_at, workflow, failed_node, left(error_message, 120) from workflow_errors order by id desc limit 10;"'

# 2. n8n's own log
kubectl -n echomind logs deploy/echomind --tail=100

# 3. Is the LLM endpoint reachable with our key? (run on the laptop; prints only the status code)
set -a; . ./.env; set +a
curl -s -o /dev/null -w '%{http_code}\n' https://ai.hackclub.com/proxy/v1/models -H "Authorization: Bearer $LLM_API_KEY"

# 4. Did a release just happen?
make history
```

In Grafana, open a failed trace in Tempo to see the exact node that failed and how long each step took.

**Fix:**

- External outage: nothing to roll back. Wait, or switch the LLM provider (see "Rotate a key or switch provider" below).
- Expired or wrong key: rotate it.
- Started right after a deploy: [roll back](#roll-back-a-release).

**Verify:** `make smoke` passes, the failure ratio on the dashboard drops below 5%, and no new rows appear in `workflow_errors`.

---

<a id="alert-echomind-n8n-down"></a>
## Alert: EchoMind - n8n not answering metrics scrapes (page)

**Fires when:** `max(up{job="n8n"})` is below 1 for 2 minutes. The collector scrapes the Service `echomind`, which only has an endpoint while the pod is Ready, so this also covers "not ready".

**Likely causes:**
- Postgres down (readiness fails).
- The n8n container crashing (for example a path it cannot write because the root filesystem is read-only).
- A release whose pod never became Ready. With `Recreate`, the old pod is already gone, so n8n stays down until Helm rolls back (up to 8 minutes).
- The `bootstrap` init container failing (for example a missing key in the Secret, or Postgres not reachable within 180 s).

**Checks:**

```sh
kubectl -n echomind get pods -o wide                                          # READY, STATUS, RESTARTS
kubectl -n echomind describe pod -l app.kubernetes.io/component=n8n | tail -30
kubectl -n echomind logs deploy/echomind -c bootstrap                          # init container output
kubectl -n echomind logs deploy/echomind -c n8n --previous --tail=50           # why the last run crashed
kubectl -n echomind get pods -l app.kubernetes.io/component=database
kubectl -n echomind get events --sort-by=.lastTimestamp | tail -20
helm history echomind -n echomind --max 5                                      # a deploy in progress or rolled back?
```

**Fix:**

- Postgres not running: check its pod and PVC; `kubectl -n echomind rollout restart statefulset/echomind-postgres`.
- Bootstrap failing on a missing variable: fix `.env`, run `make secrets`, then `kubectl -n echomind rollout restart deploy/echomind`.
- Started right after a deploy: [roll back](#roll-back-a-release).

**Verify:** the pod is `1/1 Running`, `curl http://localhost:5678/healthz/readiness` returns `200`, `make smoke` passes, and the alert resolves.

---

<a id="alert-echomind-error-handler-ran"></a>
## Alert: EchoMind - error logger workflow ran (ticket)

**Fires when:** the error logger workflow ran at least once in the last 10 minutes, meaning a production execution failed and was recorded.

**Checks:** the latest rows in `workflow_errors` (same command as in the failure-ratio alert), and the failed execution's trace in Tempo.

**Fix:** a single failure is usually an external hiccup (timeout, rate limit) and needs no action beyond reading the error. Repeated failures lead to the failure-ratio alert; handle them there.

**Verify:** no new rows in `workflow_errors` over the next 10 minutes.

---

## Procedures

<a id="first-install"></a>
### First install

```sh
cp .env.example .env    # fill in LLM_API_KEY, HUGGINGFACE_API_KEY, ECHOMIND_INGEST_TOKEN, ECHOMIND_RECALL_PASSWORD
make up
```

What to expect, from the first real install:

- The kind node pulls about 1.5 GB of images (n8n, pgvector, the observability stack). On the first real install the pull took about 7 minutes; with Postgres and n8n still starting after that, Helm's 8-minute `--rollback-on-failure` deadline expired and Helm uninstalled the release automatically. The Secrets marked `keep` and the Postgres PVC survived, so re-running `make deploy` reused the same passwords and data, and it was fast because the images were cached by then.
- While Postgres runs `initdb`, the `bootstrap` init container waits (up to 180 s) for it to accept connections. Before that wait was added, the init container crash-looped until Postgres was up.
- On first visit, `http://localhost:5678` asks you to create a local n8n owner account. No n8n.io account is involved.

If the first install was rolled back, check that the images are present (`kubectl -n echomind get events`) and run `make deploy` again.

<a id="roll-back-a-release"></a>
### Roll back a release

```sh
make history                  # find the last good revision
make rollback                 # previous revision, or: make rollback REVISION=<n>
make smoke
```

Or, from GitHub: Actions → `deploy` → "Run workflow" → `image_tag` = the previous good commit SHA. This deploys that commit's chart and image, and still needs the approval.

A rollback restores the image, the workflows and the chart. It does **not** undo n8n database migrations; this only matters if the release changed the n8n version (see "Upgrade n8n safely").

### Rotate a key or switch provider

1. Update the value in `.env` (for a new provider, also change the base URL in the chart values and the model ID in the workflows).
2. `make secrets` updates the `echomind-api-keys` Secret.
3. `kubectl -n echomind rollout restart deploy/echomind`. The `bootstrap` init container imports the credentials again on start.
4. `make smoke`.

If the ingest token or the recall password changed, give the new value to every client.

### Restore after losing the database

The workflows (in the image) and credentials (in Secrets) are imported again at every start, so a fresh database gets them back automatically. Memories, vectors and execution history only come back from a backup.

```sh
# Back up (do this regularly, and always before upgrading n8n)
kubectl -n echomind exec echomind-postgres-0 -- sh -c 'pg_dump -U "$POSTGRES_USER" -d echomind -Fc' > echomind-$(date +%F).dump
kubectl -n echomind exec echomind-postgres-0 -- sh -c 'pg_dump -U "$POSTGRES_USER" -d n8n -Fc' > n8n-$(date +%F).dump

# Restore into a fresh database
kubectl -n echomind exec -i echomind-postgres-0 -- sh -c 'pg_restore -U "$POSTGRES_USER" -d echomind --clean --if-exists' < echomind-YYYY-MM-DD.dump
kubectl -n echomind rollout restart deploy/echomind
make smoke
```

The Secret `echomind-encryption-key` is kept when the release is uninstalled, because n8n can only decrypt stored credentials with the same key. If the key is lost, the bootstrap re-imports and re-encrypts credentials from Secrets, but any other encrypted n8n settings are lost.

### Upgrade n8n safely

n8n upgrades run database migrations that cannot be reversed.

1. Dependabot opens a PR that bumps the n8n base image (tag and digest).
2. CI runs the migrations on a throwaway kind cluster. Wait for it to pass.
3. Before approving the deploy, back up both databases (commands above).
4. Approve. Afterwards check `make smoke`, the dashboard and the n8n version (`n8n_version_info`).
5. If it's bad: restore the `n8n` database from the backup, **then** roll back the image. Rolling back the image alone leaves a database migrated for the newer n8n.

## Grafana panels say "Plugin not registered"

**Symptom:** dashboard panels or Explore show `Plugin not registered` for Prometheus, Loki or Tempo.

**Cause seen during setup:** Grafana 13 replaces its bundled datasource plugins at start-up. When the
container had every Linux capability dropped, that replace failed (`unlinkat ... permission denied`)
and the datasources were left unregistered. `deploy/observability/lgtm.yaml` therefore adds back only
`CHOWN`, `DAC_OVERRIDE` and `FOWNER`.

**Check:**

```sh
kubectl -n observability logs deploy/lgtm | grep -c 'Failed to install plugin'   # expect 0
curl -s -u admin:admin 'http://localhost:3300/api/plugins?type=datasource' | grep -o '"id":"prometheus"'
```

**Fix:** `kubectl -n observability rollout restart deploy/lgtm` (plugins are installed again on start).
