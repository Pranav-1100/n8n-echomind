# Baseline

Baseline: commit [`423c114`](https://github.com/Pranav-1100/n8n-echomind/commit/423c114d6dbcbd34af931eeec994c0600eead501) ("completed assignment", 4 June 2026), preserved on `main`.

**What existed:** four n8n workflow exports (memory ingestion, memory recall, email triage, error handler) and the Readme. The workflows were built and run by hand in an n8n editor account that no longer exists; the API credentials lived only there. No containers, Kubernetes, CI/CD, tests, secret management or monitoring.

**How it was tested:** the four files, unchanged, were imported into a self-hosted n8n 2.44.3 in Docker with placeholder credentials, activated, and called.

| # | Finding at baseline | Fix in this PR |
|---|---|---|
| 1 | Ingest webhook had no authentication | `X-EchoMind-Token` header (`403` without it) |
| 2 | Ingest replied `200 "Workflow was started"` before doing the work, even when it later failed | Replies when done: `201` stored, `500` failed |
| 3 | A missing transcript also got `200` and stored nothing | `400 {"error":"transcript is required"}` |
| 4 | Recall worked only inside the n8n editor | Authenticated HTTP chat endpoint (basic auth) |
| 5 | The confidence check crashed when the LLM omitted `confidence` | Falls back to 0 ("uncertain") |
| 6 | Only workflow 1 reported failures; the error handler depended on Google Sheets | All workflows report to it; errors go to Postgres `workflow_errors` |
| 7 | The Llama 3.3 70B model is retired (NVIDIA returned `410 Gone`) | OpenAI-compatible endpoint, `deepseek/deepseek-v4.1-flash-1017` |
| 8 | Pinecone and Google credentials existed only in the old account | pgvector and Postgres tables; email triage inactive until Google OAuth |
| 9 | Files named "My Workflow (1).json" etc. | `workflows/ingest-memory.json` etc., descriptive names |
