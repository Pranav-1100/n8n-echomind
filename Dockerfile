# syntax=docker/dockerfile:1

# n8n is pinned by version and digest, so a rebuild can never silently pick up
# a different n8n. Dependabot proposes upgrades as pull requests, which then go
# through the same CI as any other change.
FROM n8nio/n8n:2.44.3@sha256:5032941f437e1daa421cad0cc3ea57cd054f0d44a7256b38a0a3fca1b460834a

USER root
# Note: the upstream image ships without a package manager (apk is removed as
# hardening), so OS packages cannot be patched here. Known findings are listed
# with a reason and an expiry date in .trivyignore.yaml until n8n ships a fix.

# The application: EchoMind's workflows plus the start-up import logic.
# Owned by root, so the n8n user can read but not modify them.
COPY workflows/ /opt/echomind/workflows/
COPY docker/bootstrap.sh docker/render-credentials.js /opt/echomind/
RUN chmod 0755 /opt/echomind/bootstrap.sh

# Build metadata from CI: every image maps back to exactly one commit.
ARG GIT_SHA=dev
ARG BUILD_TIME=unknown
ARG SOURCE_URL=""
ENV ECHOMIND_VERSION=$GIT_SHA
LABEL org.opencontainers.image.title="echomind" \
      org.opencontainers.image.description="EchoMind n8n workflows on a pinned n8n runtime" \
      org.opencontainers.image.revision=$GIT_SHA \
      org.opencontainers.image.created=$BUILD_TIME \
      org.opencontainers.image.source=$SOURCE_URL

USER node
