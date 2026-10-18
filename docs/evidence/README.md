# Evidence

Evidence that EchoMind builds, deploys and runs as described, tied to the commit it was captured for.

**Tested release:** commit `a54d420dfce0edbe2665d98e91b223b13ce4ddef`, image
`ghcr.io/pranav-1100/echomind:a54d420dfce0edbe2665d98e91b223b13ce4ddef`
(digest `sha256:dc5f68382af1d625ecc4e1dfc8a25c79d54c50581cb8f513ecdfc6620960c293`), built and tested by
[CI run 39142094458](https://github.com/Pranav-1100/n8n-echomind/actions/runs/39142094458) and deployed to the
local cluster by the approved `promote to local cluster` job of the same run (Helm revision 2).
Later commits only add this evidence, documentation and observability fixes.

## Generated files

| File | How to regenerate | Shows |
|---|---|---|
| `a54d420dfce0edbe2665d98e91b223b13ce4ddef.md` | `make evidence` | Source commit and baseline, pipeline runs for the commit, Helm history, running pods and image digests, the full user journey (ingest → recall), security checks (NetworkPolicy test, service-account permissions, drift check), telemetry (n8n version, success ratio, latency, traces, logs, alert rules) and database row counts |
| `demos/bad-release.txt` | `make demo-bad-release` | A release whose image does not exist never becomes Ready; Helm rolls back automatically (revision 3 failed → revision 4 "Rollback to 2"). Measured impact with `Recreate`: about 151 s of failed health probes |
| `demos/db-outage.txt` | `make demo-db-outage` | Postgres scaled to 0: n8n stays Running but not Ready (no restarts), requests fail fast, recovery is automatic and no data is lost |
| `demos/ai-outage.txt` | `make demo-ai-outage` | An invalid LLM key: ingest returns `500` while n8n stays healthy, the error logger writes a row to `workflow_errors`, the log-based alert fires; restoring the key restores the full journey |

`make evidence` only reads state; its one exception is the smoke test, which stores a single test memory.

**Unplanned incident during capture:** the first `make evidence` run failed at the recall step because the LLM provider
returned `504 Gateway Timeout`. EchoMind returned `500`, the error logger stored
`Memory Recall | Basic LLM Chain1 | Gateway timed out` in `workflow_errors`, and the log-based alert covers it. The re-run
passed. This is why the success SLO is 95%: the external AI services are the weakest link.

## Screenshots (`screenshots/`)

| File | Shows |
|---|---|
| `ci-run.png` | CI run for `a54d420`: validate, source scan and build + kind e2e green; image published with its digest |
| `deploy-approved.png` | The same run after approval: all four jobs green, including the deploy to the local cluster |
| `environment.png` | GitHub environment `local` with a required reviewer |
| `runner.png` | The self-hosted runner `echomind-mac` and its labels |
| `runner-deploy.png` | The runner picking up and completing the deploy job |
| `fork-approval.png` | Fork pull-request workflows require approval for all external contributors |
| `alert-rules.png` | The three provisioned EchoMind alert rules |
| `alert-firing.png` | The log-based alert firing during the LLM-outage demo |
| `alert-detail.png` | The firing alert's Loki query, threshold and runbook link |
| `alert-pending.png` | The scrape alert going Pending while n8n restarted during the demo |
| `dashboard.png` | "EchoMind - service health" dashboard |
| `trace.png` | An ingest execution trace in Tempo |
| `logs.png` | EchoMind logs in Loki |
| `n8n-executions.png` | n8n's executions list |

## Links

- Pull request: https://github.com/Pranav-1100/n8n-echomind/pull/1
- CI and deploy run for the tested release: https://github.com/Pranav-1100/n8n-echomind/actions/runs/39142094458
- Baseline commit: https://github.com/Pranav-1100/n8n-echomind/commit/423c114d6dbcbd34af931eeec994c0600eead501
