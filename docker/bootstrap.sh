#!/bin/sh
# Runs as a Kubernetes init container before n8n starts, so n8n's database
# always matches git:
#   1. credentials from Kubernetes Secrets -> n8n (encrypted on import)
#   2. workflows baked into this image     -> n8n (overwritten by ID)
#   3. only the workflows in ECHOMIND_ACTIVE_WORKFLOWS are published (active)
set -eu

# Postgres may still be starting (first boot runs initdb). Wait up to 3
# minutes for it to accept TCP connections instead of crash-looping.
node -e '
const net = require("net");
const host = process.env.DB_POSTGRESDB_HOST;
const port = Number(process.env.DB_POSTGRESDB_PORT || 5432);
const deadline = Date.now() + 180000;
(function attempt() {
  const socket = net.connect(port, host, () => { socket.end(); console.log(`database ${host}:${port} is reachable`); });
  socket.on("error", () => {
    socket.destroy();
    if (Date.now() > deadline) { console.error(`database ${host}:${port} not reachable after 180s`); process.exit(1); }
    setTimeout(attempt, 3000);
  });
})();'

umask 077
creds=/tmp/credentials.json
node /opt/echomind/render-credentials.js > "$creds"
n8n import:credentials --input="$creds"
rm -f "$creds"

# Importing deactivates every workflow; publishing below re-activates the
# ones that should run. Anything not listed (e.g. email triage) stays off.
n8n import:workflow --separate --input=/opt/echomind/workflows

for id in ${ECHOMIND_ACTIVE_WORKFLOWS:-}; do
  n8n publish:workflow --id="$id"
done

echo "bootstrap complete: version ${ECHOMIND_VERSION:-unknown}, active: ${ECHOMIND_ACTIVE_WORKFLOWS:-none}"
