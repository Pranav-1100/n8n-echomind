#!/usr/bin/env bash
# Drift check: compares the live objects with the manifest Helm last deployed.
# Any manual change (kubectl scale/edit/set image) to a field the chart sets
# shows up here. `metadata.generation` always differs in a dry run, so it is
# ignored.
#   scripts/drift.sh [namespace] [release]
# Exit codes: 0 no drift, 1 drift, 2 the check itself failed.
set -uo pipefail

NS="${1:-echomind}"
RELEASE="${2:-echomind}"

diff_out=$(helm get manifest "$RELEASE" -n "$NS" | kubectl diff -n "$NS" -f - 2>&1)
status=$?
if (( status > 1 )); then
  echo "$diff_out" >&2
  echo "drift check failed to run" >&2
  exit 2
fi

changes=$(echo "$diff_out" | grep -E '^[-+] ' | grep -vE '^[-+][[:space:]]+generation:' || true)
if [[ -z "$changes" ]]; then
  revision=$(helm status "$RELEASE" -n "$NS" -o json | sed -E 's/.*"version":([0-9]+).*/\1/')
  echo "No drift: the cluster matches Helm release $RELEASE (revision $revision)"
  exit 0
fi

echo "$diff_out" | grep -vE '^[-+][[:space:]]+generation:'
echo
echo "DRIFT: live objects differ from Helm release $RELEASE (- live, + declared). Fix by re-deploying or by committing the change."
exit 1
