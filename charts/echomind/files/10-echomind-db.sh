#!/bin/bash
# Creates EchoMind's application database (memories, vectors, error log) next
# to n8n's own database, owned by a separate least-privilege role.
set -euo pipefail
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE ROLE echomind LOGIN PASSWORD '${ECHOMIND_DB_PASSWORD}';
CREATE DATABASE echomind OWNER echomind;
SQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname echomind <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
SET ROLE echomind;
CREATE TABLE IF NOT EXISTS memories (
  id          BIGSERIAL PRIMARY KEY,
  speaker     TEXT,
  transcript  TEXT NOT NULL,
  emotion     TEXT,
  topic       TEXT,
  summary     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS workflow_errors (
  id             BIGSERIAL PRIMARY KEY,
  occurred_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  workflow       TEXT,
  failed_node    TEXT,
  error_message  TEXT,
  execution_url  TEXT
);
SQL
