# Evidence

Evidence that the system works, tied to the commit it was captured for.

## Generated files

| File | How to regenerate | Shows |
|---|---|---|
| `<sha>.md` | `make evidence` | Source commit, pipeline runs for that commit, Helm release history, running pods and image digests, the full user journey (ingest → recall), security checks (NetworkPolicy test, service-account permissions, drift check), and telemetry queries (execution success ratio, n8n version, recent traces, alert rules) |
| `demo-bad-release.txt` | `make demo-bad-release > docs/evidence/demo-bad-release.txt` | A release that never becomes Ready is rolled back automatically |
| `demo-db-outage.txt` | `make demo-db-outage > docs/evidence/demo-db-outage.txt` | Postgres outage: readiness fails, the alert fires, recovery happens with no data lost |
| `demo-ai-outage.txt` | `make demo-ai-outage > docs/evidence/demo-ai-outage.txt` | LLM endpoint failure: requests return `500`, errors are logged in `workflow_errors`, the failure-ratio alert fires |

<!-- TODO: final commit evidence file: docs/evidence/<final-sha>.md -->

`make evidence` only reads state. Its one exception is the smoke test, which stores a single test memory.

## Screenshots

<!-- TODO: add screenshots captured from the final deployment -->

| File | What to capture |
|---|---|
| `grafana-dashboard.png` | "EchoMind - service health" dashboard after a few ingest and recall requests |
| `tempo-trace.png` | One ingest execution trace in Tempo, with the LLM and database spans visible |
| `n8n-executions.png` | The n8n executions list with successful ingest and recall runs |
| `ci-run.png` | The green CI run for the final commit |
| `deploy-approved.png` | The deploy run after approval, with the release history summary |

## Links

- CI run for the final commit: <!-- TODO: link -->
- Deploy run: <!-- TODO: link -->
- Pull request: https://github.com/Pranav-1100/n8n-echomind/pull/1
