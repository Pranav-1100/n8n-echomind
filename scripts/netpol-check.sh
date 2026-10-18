#!/usr/bin/env bash
# Proves the NetworkPolicy works: a pod that is not n8n must NOT be able to
# reach Postgres, even from inside the same namespace. (n8n itself reaching
# Postgres is proven by its readiness probe, which checks the database.)
#   scripts/netpol-check.sh [namespace] [release]
set -euo pipefail

NS="${1:-echomind}"
RELEASE="${2:-echomind}"
NAME="netpol-check-$RANDOM"
IMAGE="$(kubectl -n "$NS" get statefulset "$RELEASE-postgres" -o jsonpath='{.spec.template.spec.containers[0].image}')"

# The namespace enforces the "restricted" Pod Security Standard, so even this
# throwaway pod runs as non-root with no privileges.
OVERRIDES=$(cat <<JSON
{
  "spec": {
    "automountServiceAccountToken": false,
    "securityContext": { "runAsNonRoot": true, "runAsUser": 999, "seccompProfile": { "type": "RuntimeDefault" } },
    "containers": [{
      "name": "$NAME",
      "image": "$IMAGE",
      "command": ["pg_isready", "-h", "$RELEASE-postgres", "-p", "5432", "-t", "5"],
      "securityContext": { "allowPrivilegeEscalation": false, "capabilities": { "drop": ["ALL"] } }
    }]
  }
}
JSON
)

echo "== n8n readiness (it reaches Postgres through the policy)"
kubectl -n "$NS" get pods -l app.kubernetes.io/component=n8n \
  -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[0].ready'

echo "== an unrelated pod tries to reach $RELEASE-postgres:5432 (should be blocked)"
if kubectl -n "$NS" run "$NAME" --rm -i --restart=Never --quiet --image="$IMAGE" --overrides="$OVERRIDES"; then
  echo "NETPOL FAIL: Postgres is reachable from an arbitrary pod" >&2
  exit 1
fi
echo "NETPOL OK: Postgres refused a pod that is not n8n"
