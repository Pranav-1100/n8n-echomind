# EchoMind

> This branch runs EchoMind on Kubernetes with CI/CD and observability. The description below is unchanged from the
> baseline commit [`423c114`](https://github.com/Pranav-1100/n8n-echomind/commit/423c114d6dbcbd34af931eeec994c0600eead501); see [Running EchoMind on Kubernetes](#running-echomind-on-kubernetes) for what changed.

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

# Running EchoMind on Kubernetes

## What changed in this PR

- **Workflows fixed** (`workflows/`): ingest needs a token and replies `201` / `400` / `403` / `500` when the work is done; recall is an authenticated HTTP endpoint; every workflow reports failures. See [docs/BASELINE.md](docs/BASELINE.md).
- **Services replaced** so EchoMind runs on infrastructure we control: Groq (retired model) → OpenAI-compatible endpoint (Hack Club AI), Pinecone → pgvector in Postgres, Google Sheets → Postgres tables. Email triage stays inactive until Google OAuth is set up.
- **Container image**: n8n 2.44.3 pinned by digest, workflows and a start-up bootstrap baked in, tagged with the commit SHA.
- **Kubernetes (Helm, kind)**: n8n with 1 replica, `Recreate` and probes; Postgres + pgvector StatefulSet with a PVC; secrets generated in the cluster; NetworkPolicies; restricted Pod Security.
- **CI/CD (GitHub Actions)**: validate, scan, build, test-deploy on kind, push to GHCR, then an approved deploy to the laptop cluster with automatic rollback.
- **Observability**: metrics, logs and traces in Grafana (Prometheus, Loki, Tempo), plus a dashboard and three alerts as code.
- **Operations**: scripts for smoke tests, drift checks, evidence capture and three failure demos.

## Run it locally

Prerequisites: Docker Desktop (8 GB+ memory), kind 0.33, kubectl, Helm 4, Node.js 24, make, a Hack Club AI key and a Hugging Face read token. No n8n.io account is needed.

1. `cp .env.example .env`, then fill in `LLM_API_KEY`, `HUGGINGFACE_API_KEY`, `ECHOMIND_INGEST_TOKEN` and `ECHOMIND_RECALL_PASSWORD` (`.env` is git-ignored).
2. `make up` creates the cluster, the observability stack, the image and the secrets, then deploys. The first run downloads about 1.5 GB of images.
3. Open n8n at http://localhost:5678 (it asks for a local owner account on the first visit) and Grafana at http://localhost:3300 (`admin` / `admin`, dashboard "EchoMind - service health").
4. Try it:

```sh
set -a; . ./.env; set +a

# store a memory -> 201 with a summary
curl -s -X POST http://localhost:5678/webhook/b3f32965-eaf7-4301-82ca-1945d8ff2de5 \
  -H 'content-type: application/json' -H "X-EchoMind-Token: $ECHOMIND_INGEST_TOKEN" \
  -d '{"speaker":"Pranav","transcript":"We decided to deploy EchoMind on a local kind cluster."}'

# ask about it -> 200 with the answer
curl -s -u "echomind:$ECHOMIND_RECALL_PASSWORD" -X POST \
  http://localhost:5678/webhook/9216b954-b7b0-44b2-b57a-bfd45c8940ea/chat \
  -H 'content-type: application/json' \
  -d '{"action":"sendMessage","sessionId":"demo","chatInput":"Where did we deploy EchoMind?"}'
```

## Useful commands

| Command | What it does |
|---|---|
| `make up` | Everything from scratch |
| `make deploy` | `helm upgrade --install` with `--rollback-on-failure` |
| `make smoke` | Full user journey: health, auth, ingest, recall |
| `make history` / `make rollback` | Release history / roll back (`REVISION=<n>` for a specific one) |
| `make drift` | Compare the live objects with the last Helm release |
| `make evidence` | Write `docs/evidence/<sha>.md` |
| `make demo-bad-release` | Deploy a broken release and watch Helm roll it back |
| `make demo-db-outage` | Stop Postgres, watch readiness and recovery |
| `make demo-ai-outage` | Break the LLM key, watch the failure get logged and alerted |
| `make down` | Delete the cluster |

`make help` lists every target.

## Pipeline

`.github/workflows/ci.yml` runs on every push: `validate` (workflow and script checks) and `scan-source` (Trivy), then `build-and-e2e` (build the image tagged with the commit SHA, scan it, deploy it to a throwaway kind cluster, run the smoke test, `helm test` and the NetworkPolicy test, then push it to GHCR).
`deploy-local` calls `.github/workflows/deploy.yml`, which waits for approval in the `local` environment and runs on the self-hosted runner on the laptop: pull the tested image, `helm upgrade --rollback-on-failure`, full smoke test. Running `deploy.yml` by hand with an older SHA rolls back.
All actions are pinned to commit SHAs.

## Docs

[Architecture](docs/ARCHITECTURE.md) · [Decisions](docs/DECISIONS.md) · [Runbook](docs/RUNBOOK.md) · [Baseline findings](docs/BASELINE.md) · [Evidence](docs/evidence/README.md)

## Known limitations

- One n8n replica with `Recreate`: each deploy has a short outage, and a release that never becomes Ready keeps n8n down until Helm rolls back (about 151 s in the bad-release demo). The pipeline pulls the image before `helm upgrade`, so a missing image fails the job without touching the cluster.
- Single-node cluster and a single Postgres instance: no high availability.
- The user journey depends on the external LLM endpoint and Hugging Face (availability, credits, rate limits); CI tests the platform with the health-check workflow and dummy keys.
- Email triage is inactive until Google OAuth credentials are set up.
- `grafana/otel-lgtm` is a demo image: data is lost on restart, it runs as root with the CHOWN, DAC_OVERRIDE and FOWNER capabilities (Grafana installs its datasource plugins at start-up), and Grafana uses its default login, reachable only on `127.0.0.1`.
- Deploys need the laptop and the self-hosted runner to be online.
- CI builds a `linux/amd64` image, which runs under emulation on Apple Silicon; a multi-architecture build would remove this.
- The execution success ratio also counts the health-check workflow: n8n 2.44.3 labels only the `_sum` series by workflow, so it cannot be filtered out.
- 13 CVEs in the upstream n8n image (11 in bundled libraries, 2 in Alpine packages) are accepted until 2026-11-30, each with a reason in `.trivyignore.yaml`.
- API keys used during development must be rotated after grading.

## Credits

- [n8n](https://github.com/n8n-io/n8n): workflow runtime (`n8nio/n8n` image)
- [grafana/docker-otel-lgtm](https://github.com/grafana/docker-otel-lgtm): Kubernetes manifest for the observability stack (Apache-2.0)
- [OpenTelemetry Collector](https://github.com/open-telemetry/opentelemetry-collector-contrib): metrics scrape and log shipping
- [pgvector](https://github.com/pgvector/pgvector): vector search inside Postgres
- The Helm chart started from the `helm create` scaffold
