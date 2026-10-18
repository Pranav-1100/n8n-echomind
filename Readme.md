# EchoMind

> This branch turns EchoMind into a service that is deployed, operated and observed on Kubernetes.
> The project description below is unchanged from the baseline commit
> [`423c114`](https://github.com/Pranav-1100/n8n-echomind/commit/423c114d6dbcbd34af931eeec994c0600eead501).
> Some services have been replaced since then (Groq → OpenAI-compatible LLM endpoint, Pinecone → pgvector,
> Google Sheets → Postgres). See [What changed since the baseline](#what-changed-since-the-baseline)
> and [Running EchoMind locally](#running-echomind-locally).

## Overview

EchoMind is an AI-powered personal memory and productivity assistant built using n8n.

The goal of this project is to help users store important conversations, retrieve them later using natural language, and automatically manage incoming emails. Instead of manually searching through notes, chats, or emails, users can simply ask questions and let the system find the relevant information.

This project demonstrates agentic workflow design by combining AI reasoning, deterministic logic, vector databases, workflow automation, and error handling.

---

## Problem Statement

As students and developers, we participate in many discussions every week including project meetings, mentor calls, hackathons, research discussions, and email conversations.

Important decisions and information are often forgotten after a few days.

EchoMind solves this problem by:

* Capturing conversation transcripts
* Extracting useful information using AI
* Storing memories for future retrieval
* Allowing natural language search over past conversations
* Automatically prioritizing important emails

---

## Tech Stack

* n8n
* Groq (Llama 3.3 70B)
* Pinecone Vector Database
* Hugging Face Embeddings
* Google Sheets
* Gmail API

---

# Workflow 1: Memory Ingestion Pipeline

### Purpose

Convert raw conversation transcripts into structured and searchable memories.

### Workflow

1. Receive transcript through a webhook.
2. Validate that transcript data exists.
3. Detect emotion using Llama 3.3 70B.
4. Check confidence score using a deterministic IF node.
5. Classify the conversation topic.
6. Generate a concise summary.
7. Store structured data in Google Sheets.
8. Generate embeddings.
9. Store memories in Pinecone for semantic search.

### AI Tasks

* Emotion Detection
* Topic Classification
* Summary Generation

### Deterministic Tasks

* Input Validation
* Confidence Threshold Check
* Data Storage
* Workflow Routing

---

# Workflow 2: Memory Recall Assistant

### Purpose

Allow users to retrieve past conversations using natural language questions.

### Workflow

1. Receive user query through chat.
2. Parse user intent using AI.
3. Determine retrieval strategy.
4. Search Pinecone for relevant memories.
5. Aggregate retrieved results.
6. Generate a final answer based only on retrieved memories.

### Example Query

"What is the latest update on the security pentesting project with Aditya, and what platform are we targeting next?"

---

# Workflow 3: Inbox Shield

### Purpose

Automatically summarize and prioritize incoming emails.

### Workflow

1. Monitor unread Gmail messages.
2. Generate an email summary using AI.
3. Classify email priority using AI.
4. Merge results.
5. Store summaries in Google Sheets.
6. If email is urgent, automatically apply an Important label.

### AI Tasks

* Email Summarization
* Priority Classification

### Deterministic Tasks

* Label Assignment
* Conditional Routing
* Logging

---

# Workflow 4: Global Error Handler

### Purpose

Provide centralized monitoring for workflow failures.

### Workflow

1. Capture workflow execution failures.
2. Record timestamp, workflow name, failed node, and error message.
3. Store error logs in Google Sheets.

---

## Agentic Design Concepts Demonstrated

This project demonstrates multiple agentic workflow concepts:

* Task Decomposition
* Multiple AI Agents
* Tool Usage
* Structured Outputs
* Routing Logic
* Deterministic Validation
* Vector Search
* Retrieval-Augmented Generation (RAG)
* Error Handling

---

## Sample Input

```json
{
  "speaker": "Aditya Singh",
  "transcript": "We finally got the Model Context Protocol working with Claude for the security pentesting project. Let us focus on scaling it for Code4rena next."
}
```

## Sample Output

```json
{
  "emotion": "excited",
  "topic": "coding",
  "summary": "The discussion focused on successfully integrating Model Context Protocol with Claude for a security pentesting project and planning future scaling efforts for Code4rena."
}
```

---

## Future Improvements

* Real-time audio ingestion
* Mobile application
* Human-in-the-loop review interface
* Custom backend service
* Speaker identification
* Real-time meeting integration

---

## Author

Pranav Aggarwal

---

# Deploying and operating EchoMind

## What changed since the baseline

| Concern | Baseline (`423c114`) | Now |
|---|---|---|
| Runtime | Workflows set up by hand in an n8n editor account | n8n 2.44.3 on Kubernetes (kind), deployed with Helm |
| Workflows | Four exports in the repo root, imported by hand | `workflows/*.json`, baked into the image and imported automatically at start-up |
| LLM | Groq, Llama 3.3 70B (model family since retired) | OpenAI-compatible endpoint (Hack Club proxy), model `deepseek/deepseek-v4.1-flash-1017` |
| Vector store | Pinecone index `echomind-n8n` | pgvector in our own Postgres (table `memory_vectors`) |
| Structured memories / error log | Google Sheets | Postgres tables `memories` and `workflow_errors` |
| Embeddings | Hugging Face `sentence-transformers/all-MiniLM-L6-v2` | Unchanged (384 dimensions) |
| Email triage | Gmail + Sheets | Kept in the repo, inactive until Google OAuth is set up |
| Ingest webhook | No authentication, replied "Workflow was started" before doing any work | Token in `X-EchoMind-Token`; replies `201` / `400` / `403` / `500` when the work is done |
| Recall chat | Usable only inside the n8n editor | Authenticated HTTP endpoint (basic auth) |

[docs/BASELINE.md](docs/BASELINE.md) lists every baseline finding and its fix.

## Running EchoMind locally

### Prerequisites

- Docker Desktop with at least 8 GB of memory
- kind 0.33, kubectl, Helm 4, Node.js 24, make
- gh (optional, only used by `make evidence` to list the CI runs for a commit)
- A Hack Club AI key (or any OpenAI-compatible endpoint, see `llm.baseUrl` in `charts/echomind/values.yaml`) and a Hugging Face token with read access

No n8n.io account is needed: n8n runs self-hosted, and on the first visit the editor asks you to create a local owner account.

### Start everything

```sh
cp .env.example .env   # fill in the four values below; .env is git-ignored
make up                # kind cluster, observability stack, image build, secrets, Helm deploy, smoke test
```

| `.env` variable | Used for |
|---|---|
| `LLM_API_KEY` | Key for the OpenAI-compatible LLM endpoint (Hack Club AI by default) |
| `HUGGINGFACE_API_KEY` | Hugging Face embeddings (`sentence-transformers/all-MiniLM-L6-v2`) |
| `ECHOMIND_INGEST_TOKEN` | Value clients send in `X-EchoMind-Token` to the ingest webhook |
| `ECHOMIND_RECALL_PASSWORD` | Basic-auth password (user `echomind`) for the recall chat |

`make secrets` copies these four values into the Kubernetes Secret `echomind-api-keys`; they never go into git, Helm values or CI logs.

The first `make up` downloads about 1.5 GB of images into the kind node (n8n, pgvector, the observability stack), so it takes several minutes. Later runs reuse them.

| What | URL |
|---|---|
| n8n editor | http://localhost:5678 |
| Grafana (dashboard "EchoMind - service health") | http://localhost:3300 |

Both ports are bound to `127.0.0.1` only.

### Try it

```sh
set -a; . ./.env; set +a

# Health check (no auth, no external calls)
curl -s http://localhost:5678/webhook/echomind-health

# Store a memory
curl -s -X POST http://localhost:5678/webhook/b3f32965-eaf7-4301-82ca-1945d8ff2de5 \
  -H 'content-type: application/json' \
  -H "X-EchoMind-Token: $ECHOMIND_INGEST_TOKEN" \
  -d '{"speaker":"Pranav","transcript":"In the mentor call we decided to deploy EchoMind on a local kind cluster instead of AWS."}'

# Ask about it
curl -s -u "echomind:$ECHOMIND_RECALL_PASSWORD" \
  -X POST http://localhost:5678/webhook/9216b954-b7b0-44b2-b57a-bfd45c8940ea/chat \
  -H 'content-type: application/json' \
  -d '{"action":"sendMessage","sessionId":"demo","chatInput":"Where did we decide to deploy EchoMind?"}'
```

| Endpoint | Response |
|---|---|
| Ingest | `201` stored (with the summary), `400` transcript missing, `403` token missing or wrong, `500` processing failed (the error is logged) |
| Recall | `200` with the answer, `401` without the login, `500` processing failed |

Measured locally: ingest takes about 7–13 s (three LLM calls plus embeddings), recall about 2.6 s.

### Make targets

`make help` lists them all.

| Command | What it does |
|---|---|
| `make up` | Everything from scratch: cluster, observability, build, load, secrets, deploy, smoke |
| `make validate` | Checks the workflow files (`scripts/validate-workflows.mjs`) |
| `make cluster` | Creates the kind cluster from `deploy/kind/kind-config.yaml` |
| `make observability` | Applies `deploy/observability` (Grafana LGTM stack, collector, dashboard, alerts) |
| `make build` / `make load` | Builds the image tagged with the current commit SHA / copies it into the kind node |
| `make secrets` | Creates or updates the `echomind-api-keys` Secret from `.env` |
| `make deploy` | `helm upgrade --install` with `--rollback-on-failure` |
| `make smoke` / `make smoke-ci` | Full user journey (real AI calls) / the CI subset (health, `403`, `400`) |
| `make helm-test` | Runs the chart's in-cluster test (calls the health-check workflow) |
| `make netpol-check` | Proves that a pod other than n8n cannot reach Postgres |
| `make history` / `make rollback` | Release history / roll back (`REVISION=<n>` for a specific one) |
| `make drift` | Compares the live objects with the last Helm release |
| `make evidence` | Writes `docs/evidence/<sha>.md` |
| `make demo-bad-release` / `make demo-db-outage` / `make demo-ai-outage` | Failure demonstrations |
| `make logs` | n8n logs |
| `make grafana` / `make n8n` | Opens Grafana / the n8n editor |
| `make down` | Deletes the local cluster |

## Delivery pipeline

`.github/workflows/ci.yml` runs on every push (all branches), on pull requests from forks, and on manual dispatch:

| Job | What it does |
|---|---|
| `validate` | `scripts/validate-workflows.mjs` on `workflows/`; syntax checks of `scripts/*.sh`, `docker/bootstrap.sh` and `docker/render-credentials.js` |
| `scan-source` | Trivy scan of the repository: vulnerabilities, secrets and misconfigurations, failing on fixable HIGH/CRITICAL |
| `build-and-e2e` | Builds the image tagged with the full commit SHA, Trivy image scan, `helm lint`, creates a throwaway kind cluster from the same `deploy/kind/kind-config.yaml`, creates dummy secrets, deploys with `values-ci.yaml`, runs `SMOKE_MODE=ci scripts/smoke.sh` (health check, `403` without a token, `400` without a transcript, running version), `helm test` and `scripts/netpol-check.sh`, and only then pushes the image to GHCR |
| `deploy-local` | On pushes only: calls `.github/workflows/deploy.yml` with the same commit SHA |

`.github/workflows/deploy.yml` (job `deploy`) promotes that exact image to the laptop's cluster. It runs on a self-hosted runner (labels `self-hosted`, `echomind-local`) behind the GitHub environment `local`, which needs a reviewer's approval. Its steps: validate the SHA, pull the CI-built image and load it into kind, check that the `echomind-api-keys` Secret exists, `helm upgrade --install --rollback-on-failure --wait --timeout 8m` with `values-local.yaml`, run the full smoke test (real ingest and recall), and write the release history to the run summary. Running it by hand with an older SHA rolls back.

All GitHub Actions are pinned to commit SHAs. Dependabot proposes updates for the actions and for the n8n base image.

## Observability

- An OpenTelemetry Collector (`otel/opentelemetry-collector-contrib:0.162.0`, DaemonSet in namespace `observability`) scrapes n8n's `/metrics` every 15 s as job `n8n` and tails the EchoMind pod logs from `/var/log/pods`. Those log files belong to root, so the collector runs as uid 0, with no capabilities, no privilege escalation, a read-only root filesystem and a read-only log mount.
- n8n sends its own traces (one span per workflow execution and node) to Tempo over OTLP.
- Grafana (`grafana/otel-lgtm:0.36.0`) has the dashboard "EchoMind - service health" and three alert rules, all provisioned from `deploy/observability/grafana/`. [docs/RUNBOOK.md](docs/RUNBOOK.md) explains each alert.

## Operations

| Task | How |
|---|---|
| Release history | `make history` (each revision's description records the SHA and CI run) |
| Roll back | `make rollback` (previous release) or `make rollback REVISION=<n>`; or run the `deploy` workflow with an older SHA |
| Detect manual changes | `make drift` compares the live objects with the last Helm release |
| Capture evidence | `make evidence` writes `docs/evidence/<sha>.md` |
| Failure demos | `make demo-bad-release`, `make demo-db-outage`, `make demo-ai-outage` |

[docs/RUNBOOK.md](docs/RUNBOOK.md) covers alerts and recovery procedures, and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DECISIONS.md](docs/DECISIONS.md) explain the design.

## Repository layout

```
workflows/              n8n workflow exports (the application) and a health-check workflow
docker/                 start-up import: bootstrap.sh, render-credentials.js
Dockerfile              pinned n8n image + workflows
charts/echomind/        Helm chart: n8n, Postgres/pgvector, secrets, network policies, helm test
deploy/kind/            local cluster config (the same file is used in CI)
deploy/observability/   Grafana LGTM stack, OpenTelemetry Collector, dashboard, alert rules
scripts/                workflow validation, smoke test, secrets, drift check, evidence, failure demos
.github/                CI, CD, Dependabot
docs/                   baseline, architecture, decisions, runbook, evidence
```

## Known limitations

- One n8n replica with the `Recreate` strategy. Every deploy causes a short outage, and a release that never becomes Ready keeps n8n down until Helm rolls it back (at most the 8-minute `--timeout`). This is deliberate (see DECISIONS.md #2); queue mode is the path to scaling and availability.
- Single-node local cluster and a single Postgres instance: there is no high availability.
- The real user journey depends on the external LLM endpoint and Hugging Face (availability, credits, rate limits). CI therefore tests the platform with the health-check workflow and dummy keys.
- Email triage is inactive until Google OAuth credentials are set up.
- The observability stack (`grafana/otel-lgtm`) is a demo image: its data is lost on restart, it runs as root without a read-only root filesystem and keeps three file-ownership capabilities (CHOWN, DAC_OVERRIDE, FOWNER) so Grafana can install its datasource plugins at start-up, and Grafana uses its default login (reachable only on `127.0.0.1`).
- Deploys need the laptop and the self-hosted runner to be online.
- 13 CVEs in the upstream n8n 2.44.3 image are accepted until 2026-11-30, pending an upstream fix: 11 in JavaScript libraries bundled inside n8n (simple-git, @simple-git/argv-parser, handlebars, toml, nodemailer) and 2 in Alpine OS packages (tiff, libexpat). The image ships without a package manager, so we cannot patch them ourselves. Each one is listed with a reason in `.trivyignore.yaml`.
- API keys used during development must be rotated after grading.

## Credits

- [n8n](https://github.com/n8n-io/n8n): workflow runtime (`n8nio/n8n` image)
- [grafana/docker-otel-lgtm](https://github.com/grafana/docker-otel-lgtm): Kubernetes manifest for the observability stack (Apache-2.0)
- The Helm chart started from the `helm create` scaffold
- [pgvector](https://github.com/pgvector/pgvector): vector search inside Postgres (`pgvector/pgvector` image)
