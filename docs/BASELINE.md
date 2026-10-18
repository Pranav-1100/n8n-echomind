# Baseline

The starting point for the DevOps work is commit
[`423c114d6dbcbd34af931eeec994c0600eead501`](https://github.com/Pranav-1100/n8n-echomind/commit/423c114d6dbcbd34af931eeec994c0600eead501)
("completed assignment", 4 June 2026). It is preserved on `main`. All changes are in one pull request on top of it.

## What existed

| File | Content |
|---|---|
| `My Workflow (1).json` | Memory ingestion: webhook → validate → emotion, topic and summary from an LLM → Google Sheets → Hugging Face embeddings → Pinecone |
| `My Workflow 2 (1).json` | Memory recall: chat trigger → intent parsing → Pinecone search → answer from the retrieved memories |
| `My Workflow 3 (1).json` | Email triage: Gmail trigger → priority and summary → Google Sheets → label urgent mail |
| `My Workflow 4 (1).json` | Error handler: any failure → row in Google Sheets |
| `Readme.md` | Project description |

## How it was run

The workflows were built and run by hand in an n8n editor account that is no longer available. The API credentials (Groq, Pinecone, Hugging Face, Google) lived only inside that account. The repository holds exports, not a deployable system.

| Area | At baseline |
|---|---|
| Deployment | Manual, in the n8n editor |
| Containers | None |
| Kubernetes | None |
| CI/CD | None |
| Automated tests | None |
| Secret management | None in the repo; credentials only in the old n8n account |
| Observability | n8n's built-in execution list, plus the error workflow writing to Google Sheets |
| Security controls | None; the ingest webhook was reachable by anyone who knew its URL |

## How the baseline was tested

We imported the four files, unchanged, into a self-hosted n8n 2.44.3 running in Docker (no n8n.io account needed), loaded placeholder credentials, activated the workflows and called the webhooks.

| # | Finding at baseline | Fix in this PR |
|---|---|---|
| 1 | The ingest webhook had no authentication; anyone with the URL could trigger LLM calls | Header auth with `X-EchoMind-Token` (without it → `403`) |
| 2 | The ingest webhook replied `200 "Workflow was started"` before doing any work, even when the run later failed | Responds when the work is done: `201` stored, `500` failed |
| 3 | A request without a transcript also got `200`, ran as a "successful" execution and stored nothing | `400 {"error":"transcript is required"}` |
| 4 | The recall chat could only be used inside the n8n editor | Public chat endpoint protected by basic auth |
| 5 | The confidence check (`If1`) read the regex match with `[1]` and crashed when the LLM reply had no `confidence` | Falls back to `0`, so the memory is tagged "uncertain" |
| 6 | Only workflow 1 reported failures to the error handler | Workflows 1–3 all report to it |
| 7 | The error handler itself depended on Google Sheets; when Google failed, the failure was lost too | Errors go to the Postgres table `workflow_errors`, and the failure ratio and logs are monitored independently |
| 8 | The Llama 3.3 70B model family the workflows used is retired (NVIDIA's API returned `410 Gone`, end of life 2026-08-26) | OpenAI-compatible endpoint with `deepseek/deepseek-v4.1-flash-1017`, picked after testing the available models |
| 9 | Pinecone and Google credentials existed only in the old n8n account | Pinecone replaced by pgvector in our Postgres; Sheets replaced by Postgres tables; email triage kept but inactive until Google OAuth is set up |
| 10 | Workflow names were "My workflow", "My workflow 2", … and the files had spaces in their names | `workflows/ingest-memory.json` and so on, with descriptive workflow names |

Things that worked at baseline and were kept: health endpoints (`/healthz`, `/healthz/readiness`), the workflow IDs (the error-handler link survives import), and importing workflows and credentials from files with the n8n CLI.
