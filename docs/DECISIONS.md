# Decisions

### 1. Keep n8n
Decision: deploy the existing n8n workflows instead of rewriting them as code.
Why: the workflows are the application being compared with the baseline; a rewrite would replace it.
Instead when: the logic outgrows n8n (complex tests, heavy custom code).

### 2. One n8n replica with `Recreate`
Decision: a single n8n main process, old pod stopped before the new one starts.
Why: in regular mode every instance runs the triggers, so two pods would fire each trigger twice and race on DB migrations.
Cost: each deploy has a short outage; a release that never becomes Ready caused about 151 s of downtime in the demo.
Instead when: availability matters: queue mode (main + workers + Redis) or multi-main.

### 3. Workflows baked into the image, imported at start-up
Decision: `workflows/*.json` are copied into the image; the `bootstrap` init container imports them and the credentials on every start.
Why: git is the source of truth and every image SHA is exactly one set of workflows, so releases and rollbacks are traceable.
Instead when: workflows change daily: a ConfigMap and import job, or n8n's source-control feature.

### 4. pgvector and Postgres tables instead of Pinecone and Google Sheets
Decision: vectors in `memory_vectors`, memories and errors in Postgres tables.
Why: the old credentials were gone, and keeping data in our own database removes two external accounts and keeps backups in one place.
Instead when: the vector set grows beyond one Postgres instance.

### 5. OpenAI-compatible LLM endpoint (Hack Club AI)
Decision: `deepseek/deepseek-v4.1-flash-1017` through `https://ai.hackclub.com/proxy/v1`.
Why: the Llama 3.3 70B model used at baseline is retired; NVIDIA's models were retired, unavailable (404) or timed out; this one returned valid JSON in about 2 s.
Instead when: a different provider is needed: change `llm.baseUrl` and the key, no workflow change.

### 6. One Helm chart with per-environment values
Decision: `values.yaml` holds the defaults; `values-local.yaml` and `values-ci.yaml` override only what differs.
Why: no drifting copies of manifests; `image.tag` is required, so every release is a commit SHA.
Instead when: many environments: Kustomize overlays or Argo CD ApplicationSets.

### 7. Local kind cluster, not AWS or Hack Club Nest
Decision: kind on the laptop; CI builds the same cluster from the same config.
Why: the brief allows local Kubernetes, it costs nothing, and n8n needs no public URL here.
Instead when: real users: managed Kubernetes, managed Postgres and a secrets manager.

### 8. Push-based deploy through a self-hosted runner with an approval
Decision: `deploy.yml` runs on a runner on the laptop, behind the `local` environment's required reviewer.
Why: GitHub cannot reach a local cluster, and a human gate suits a one-person project. Only push events deploy, and fork PRs need approval.
Instead when: several clusters: Argo CD (pull-based, built-in drift detection).

### 9. Image tag = commit SHA; actions pinned to SHAs
Decision: images are tagged with the full SHA; every GitHub Action is pinned to a commit.
Why: traceability from pod to commit; action tags can be moved (trivy-action tags were hijacked in March 2026).
Instead when: never for production; Dependabot keeps the pins current.

### 10. grafana/otel-lgtm, and a log-based failure alert
Decision: one small observability stack; the "webhook execution failed" alert reads Loki, not Prometheus.
Why: one manifest gives metrics, logs and traces locally. n8n keeps its counters in memory, so a restart resets them, and a series that first appears at 1 is invisible to `increase()`: the metric-based alert missed a real failure. The log line survives restarts.
Instead when: production: kube-prometheus-stack, Loki and Tempo with persistent storage.

### 11. Layered security controls
Decision: secrets never in git (generated in the cluster or loaded from a git-ignored `.env`); non-root containers with read-only root filesystems and no capabilities; restricted Pod Security; NetworkPolicies (Postgres only from n8n, n8n egress only to Postgres, DNS, the collector and public HTTPS); Trivy fails CI on fixable HIGH/CRITICAL findings, with 13 upstream n8n CVEs and one demo-image misconfiguration accepted in `.trivyignore.yaml` with reasons and a 2026-11-30 expiry.
Why: each layer limits a different failure: leaked repo, compromised workflow, vulnerable dependency.
Instead when: production: External Secrets or Vault, an egress proxy with an allow-list, signed images.
