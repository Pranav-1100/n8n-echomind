# Design decisions

Short records of the main choices: the situation, what we chose, what else we considered, and when we would choose differently.

## 1. Keep n8n instead of rewriting the workflows as code

- **Context:** EchoMind is four n8n workflows. The baseline to compare against is those workflows.
- **Decision:** Keep n8n as the runtime. Treat the workflow JSON files as the application source, version them in git, validate them in CI and ship them in the image.
- **Alternatives:** Rewrite as a Node/Python service. That would replace the application being compared and take much longer.
- **Choose differently when:** The logic outgrows what workflows express well, or you need unit tests at the function level.

## 2. One n8n replica with the `Recreate` strategy

- **Context:** In n8n's regular mode, every main instance runs the triggers and webhooks. Two instances would poll and execute twice, and both would run database migrations on start.
- **Decision:** `replicas: 1`, `strategy: Recreate`. Correctness matters more than avoiding a few seconds of downtime per deploy.
- **Cost:** With `Recreate`, the old pod is gone before the new one starts. A release that never becomes Ready therefore means downtime until Helm's `--rollback-on-failure` restores the previous revision (up to the 8-minute `--timeout`). A rolling update would have kept the old pod serving.
- **Alternatives:** A rolling update with two instances briefly overlapping (duplicate triggers, concurrent migrations).
- **Choose differently when:** You need throughput or availability. Then use queue mode (main + workers + Redis) to scale executions, and multi-main (enterprise licence) for high availability.

## 3. Workflows baked into the image, imported at start-up

- **Context:** The baseline was set up by clicking in the editor, so the running state could not be traced to git.
- **Decision:** The image holds `workflows/`. The `bootstrap` init container waits for Postgres (up to 180 s), imports credentials from Secrets, imports the workflows (overwriting by ID), and publishes only the IDs listed in `n8n.activeWorkflows`. Image tag = commit SHA = one exact set of workflows.
- **Alternatives:** A ConfigMap plus an import Job; n8n's source-control feature (enterprise); editing by hand in the UI.
- **Choose differently when:** Non-developers edit workflows in the UI. Then export-and-commit, or n8n's git integration, fits better.

## 4. pgvector instead of Pinecone

- **Context:** The Pinecone index and credentials lived in an account we no longer use, and the goal was to run locally.
- **Decision:** The pgvector extension in the same Postgres (database `echomind`, table `memory_vectors`).
- **Alternatives:** Keep Pinecone (another external dependency and account); n8n's in-memory vector store (lost on restart).
- **Choose differently when:** Vector volume or query load outgrows one Postgres, or a managed service with an SLA is required.

## 5. Postgres tables instead of Google Sheets

- **Context:** Sheets needed Google OAuth tied to a personal account, and the error log itself failed whenever Google failed.
- **Decision:** `memories` and `workflow_errors` tables, written with parameterised queries by a separate least-privilege role.
- **Alternatives:** Keep Sheets (manual OAuth, external dependency).
- **Choose differently when:** Non-technical users need to browse the data in a spreadsheet.

## 6. OpenAI-compatible LLM endpoint (Hack Club proxy) instead of Groq or NVIDIA

- **Context:** The Llama 3.3 70B models the baseline used are retired (NVIDIA returned `410 Gone`). On NVIDIA's API, the other candidates we tested returned `404` for our key or timed out after 45–90 s.
- **Decision:** n8n's OpenAI chat-model node pointing at `https://ai.hackclub.com/proxy/v1`, model `deepseek/deepseek-v4.1-flash-1017`. It returned valid JSON in about 2 s in our test.
- **Alternatives:** Groq, NVIDIA, OpenAI directly, a local model (Ollama: too heavy for a laptop cluster).
- **Choose differently when:** Credits or limits run out. Switching provider is a credential change (base URL and key) plus the model ID.

## 7. One Helm chart with per-environment values files

- **Context:** The same deployment runs on the laptop and in CI.
- **Decision:** `charts/echomind`, scaffolded with `helm create`. `values.yaml` holds the defaults; `values-local.yaml` and `values-ci.yaml` hold only the differences. The image tag is required.
- **Alternatives:** Raw manifests (copies drift); Kustomize overlays.
- **Choose differently when:** The team already standardises on Kustomize or on GitOps-managed overlays.

## 8. Local kind cluster instead of AWS or Hack Club Nest

- **Context:** The brief accepts local Kubernetes; paid infrastructure is not required.
- **Decision:** kind (Kubernetes 1.37), with the same config file locally and in CI.
- **Alternatives:** AWS EKS (cost and setup time); Hack Club Nest (needs approval, shared, and nothing confirms Kubernetes support).
- **Choose differently when:** There are real users. Then use EKS with RDS (Postgres + pgvector), Secrets Manager and a Gateway with TLS.

## 9. Push-based deploy through a self-hosted runner, with an approval

- **Context:** GitHub-hosted runners cannot reach a cluster on a laptop.
- **Decision:** `deploy.yml` runs on a self-hosted runner (label `echomind-local`) behind the GitHub environment `local`, which requires a reviewer. It is triggered only by pushes and manual dispatch, never by pull requests from forks.
- **Alternatives:** Argo CD (pull-based GitOps, with drift detection and self-healing built in); running `make deploy` by hand.
- **Choose differently when:** There is more than one cluster or person. Then Argo CD with the image tag committed to git.

## 10. Image tag = full commit SHA

- **Context:** The running version must trace back to a commit.
- **Decision:** CI tags the image with `github.sha`. The chart refuses to render without a tag, OCI labels record the revision, and Helm release descriptions record the SHA and CI run.
- **Alternatives:** Semantic versions; `latest` (not traceable).
- **Choose differently when:** You publish releases for others. Then add semantic-version tags as well, alongside the SHA.

## 11. Trivy policy with explicit, expiring exceptions

- **Context:** The upstream `n8nio/n8n:2.44.3` image has 13 fixable HIGH/CRITICAL findings that only n8n can fix: 11 in JavaScript libraries bundled inside n8n (simple-git, @simple-git/argv-parser, handlebars, toml, nodemailer) and 2 in Alpine OS packages (tiff, libexpat). We first tried `apk upgrade` in our Dockerfile, but the image ships without a package manager, so we cannot patch them.
- **Decision:** CI fails on fixable HIGH/CRITICAL findings, except the 13 entries in `.trivyignore.yaml`. Each one says why the vulnerable code is not reachable in EchoMind (for example: no Git node, no SMTP, no TIFF or untrusted XML input) and expires on 2026-11-30, so it has to be reviewed again. Dependabot proposes n8n upgrades. One misconfiguration finding is also accepted: KSV-0014 (no read-only root filesystem) for `deploy/observability/lgtm.yaml` only, because the third-party demo image writes to its own filesystem at start-up.
- **Alternatives:** Fail on everything (CI permanently red); ignore everything.
- **Choose differently when:** Running in production. Then add image signing and an admission policy, and track the exceptions in an issue.

## 12. NetworkPolicy with egress on 443 to the internet

- **Context:** n8n must call the LLM endpoint and Hugging Face, but nothing else should be reachable.
- **Decision:** n8n may reach Postgres (5432), DNS, the collector, and port 443 outside the cluster. Postgres accepts traffic only from n8n and has no egress. Everything else is denied.
- **Alternatives:** No policies (any pod can reach the database); an allow-list of vendor IPs (they change often).
- **Choose differently when:** You have strict compliance needs. Then use an egress proxy or an FQDN-aware policy (for example Cilium).

## 13. grafana/otel-lgtm instead of kube-prometheus-stack + Loki + Tempo

- **Context:** We need metrics, logs and traces on a laptop with limited memory.
- **Decision:** The all-in-one `grafana/otel-lgtm:0.36.0` image, based on Grafana's own Kubernetes manifest, plus an OpenTelemetry Collector DaemonSet (`otel/opentelemetry-collector-contrib:0.162.0`) that scrapes n8n's `/metrics` as job `n8n` and tails the EchoMind pod logs from `/var/log/pods`. n8n sends its own traces over OTLP.
- **Trade-off:** The pod log files belong to root, so the collector runs as uid 0. It gets no capabilities, no privilege escalation, a read-only root filesystem and a read-only log mount.
- **Alternatives:** kube-prometheus-stack with Loki and Tempo (production-grade, several GB of memory); only `kubectl logs` for logs.
- **Choose differently when:** Running in production. The demo image keeps no data across restarts and runs as root.

## 14. NodePort through kind port mappings instead of an ingress controller

- **Context:** Only local access is needed. ingress-nginx was retired in March 2026.
- **Decision:** A NodePort Service reached through kind's port mapping, bound to `127.0.0.1`.
- **Alternatives:** Gateway API (for example Envoy Gateway); `kubectl port-forward`.
- **Choose differently when:** Exposing EchoMind to other machines. Then use Gateway API with TLS.

## 15. Secrets generated in the cluster and kept on uninstall

- **Context:** n8n needs database passwords and an encryption key. If the encryption key changes, every stored credential becomes unreadable; if a password changes, the existing Postgres volume rejects it.
- **Decision:** The chart generates `echomind-db` and `echomind-encryption-key` on the first install, reuses them on every upgrade (Helm `lookup`), and marks them `helm.sh/resource-policy: keep`. API keys are not in the chart at all: `make secrets` creates `echomind-api-keys` from `.env`.
- **Evidence:** The first real install took about 7 minutes because the kind node had to pull about 1.5 GB of images. Helm's 8-minute `--rollback-on-failure` deadline expired and Helm uninstalled the release automatically. The kept Secrets and the Postgres PVC survived, so the next install reused the same passwords and data without any manual step.
- **Alternatives:** Passwords in values files (they end up in git or CI logs); External Secrets or Sealed Secrets (more moving parts for one laptop).
- **Choose differently when:** Running in a shared cluster or the cloud. Then use External Secrets with a secret manager.

## 16. Read-only root filesystem with explicit writable folders

- **Context:** The restricted Pod Security Standard and Trivy both push for a read-only root filesystem. n8n writes to a few folders at runtime.
- **Decision:** The root filesystem is read-only, with `emptyDir` volumes for `/home/node/.n8n`, `/tmp` and `/home/node/.cache`. On the first deploy, n8n crashed with `ENOENT: mkdir '/home/node/.cache'` because it compiles its editor assets there; adding that one volume fixed it, and nothing else needed to be writable.
- **Alternatives:** A writable root filesystem (simpler, but any compromise can change the installed n8n code).
- **Choose differently when:** A future n8n version needs more writable paths. Then add them one at a time rather than making the whole root filesystem writable.
