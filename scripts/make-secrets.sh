#!/usr/bin/env bash
# Creates or updates the Kubernetes Secret "echomind-api-keys" that n8n imports
# its credentials from. Values come from .env (git-ignored) and reach kubectl
# through a private temp file that is deleted on exit, so they never appear in
# shell history, process lists or logs.
#   scripts/make-secrets.sh [namespace]           # from .env
#   scripts/make-secrets.sh --dummy [namespace]   # placeholder values for CI
# n8n reads the Secret at start-up: restart it after changing a value
#   kubectl -n echomind rollout restart deploy/echomind
set -euo pipefail

dummy=false
if [[ "${1:-}" == "--dummy" ]]; then
  dummy=true
  shift
fi
NS="${1:-echomind}"
KEYS=(LLM_API_KEY HUGGINGFACE_API_KEY ECHOMIND_INGEST_TOKEN ECHOMIND_RECALL_PASSWORD)
cd "$(dirname "$0")/.."

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
chmod 600 "$tmp"

if $dummy; then
  printf '%s\n' \
    "LLM_API_KEY=ci-dummy-llm-key" \
    "HUGGINGFACE_API_KEY=ci-dummy-hf-key" \
    "ECHOMIND_INGEST_TOKEN=ci-ingest-token" \
    "ECHOMIND_RECALL_PASSWORD=ci-recall-password" > "$tmp"
else
  [[ -f .env ]] || { echo "missing .env: copy .env.example to .env and fill it in" >&2; exit 1; }
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
  for key in "${KEYS[@]}"; do
    [[ -n "${!key:-}" ]] || { echo "$key is empty in .env" >&2; exit 1; }
    printf '%s=%s\n' "$key" "${!key}" >> "$tmp"
  done
fi

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
kubectl -n "$NS" create secret generic echomind-api-keys --from-env-file="$tmp" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "secret echomind-api-keys is up to date in namespace $NS (values not shown)"
