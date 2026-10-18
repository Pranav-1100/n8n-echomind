# One entry point for the local workflow. `make help` lists the targets.
SHELL := /bin/bash

CLUSTER   ?= echomind
NAMESPACE ?= echomind
RELEASE   ?= echomind
IMAGE     ?= echomind
BASE_URL  ?= http://localhost:5678
# Images are tagged with the commit they were built from. Uncommitted changes
# get a -dirty suffix so a local build is never mistaken for a reviewed commit.
TAG       ?= $(shell git rev-parse HEAD)$(shell git diff --quiet HEAD 2>/dev/null || echo -dirty)

.PHONY: help validate cluster observability build load secrets namespace deploy up smoke smoke-ci \
        helm-test netpol-check history rollback drift evidence demo-bad-release demo-db-outage \
        demo-ai-outage logs grafana n8n down

help: ## List targets
	@grep -E '^[a-z0-9-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-17s %s\n", $$1, $$2}'

validate: ## Check the workflow files (structure, credentials, no inline secrets)
	node scripts/validate-workflows.mjs

cluster: ## Create the kind cluster (skips if it exists)
	@kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config deploy/kind/kind-config.yaml

observability: ## Deploy Grafana/Prometheus/Loki/Tempo, the collector, dashboard and alerts
	kubectl apply -k deploy/observability
	kubectl -n observability rollout status deploy/lgtm --timeout=600s
	kubectl -n observability rollout status daemonset/otel-collector --timeout=300s

build: ## Build the image, tagged with the commit SHA
	docker build --build-arg GIT_SHA=$(TAG) --build-arg BUILD_TIME=$$(date -u +%Y-%m-%dT%H:%M:%SZ) -t $(IMAGE):$(TAG) .

load: ## Copy the image into the kind node
	kind load docker-image $(IMAGE):$(TAG) --name $(CLUSTER)

secrets: ## Create/update the API-key Secret from .env (values never printed)
	scripts/make-secrets.sh $(NAMESPACE)

namespace:
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace $(NAMESPACE) pod-security.kubernetes.io/enforce=restricted --overwrite

deploy: namespace ## Helm upgrade; rolls back automatically if n8n never becomes ready
	helm upgrade --install $(RELEASE) charts/echomind -n $(NAMESPACE) \
	  -f charts/echomind/values-local.yaml \
	  --set image.repository=$(IMAGE) --set image.tag=$(TAG) \
	  --rollback-on-failure --wait --timeout 8m \
	  --description "make deploy sha=$(TAG)"

up: cluster observability build load secrets deploy smoke ## Everything from scratch on a laptop

smoke: ## Full user journey (health, auth, validation, ingest, recall)
	scripts/smoke.sh $(BASE_URL)

smoke-ci: ## Platform checks only (no external AI calls)
	SMOKE_MODE=ci scripts/smoke.sh $(BASE_URL)

helm-test: ## Run the in-cluster helm test
	helm test $(RELEASE) -n $(NAMESPACE) --logs

netpol-check: ## Prove that only n8n can reach Postgres
	scripts/netpol-check.sh $(NAMESPACE) $(RELEASE)

history: ## Release history: revision, image, description
	helm history $(RELEASE) -n $(NAMESPACE)

rollback: ## Roll back to the previous release (or REVISION=n)
	helm rollback $(RELEASE) $(REVISION) -n $(NAMESPACE) --wait --timeout 8m

drift: ## Compare live objects with what Helm last deployed
	scripts/drift.sh $(NAMESPACE) $(RELEASE)

evidence: ## Capture verification evidence for the running version
	scripts/evidence.sh

demo-bad-release: ## Fault demo: deploy a broken image and watch it roll back
	scripts/demo-bad-release.sh

demo-db-outage: ## Fault demo: stop Postgres, observe, recover, verify
	scripts/demo-db-outage.sh

demo-ai-outage: ## Fault demo: invalid LLM key, see the failure logged and alerted, restore
	scripts/demo-ai-outage.sh

logs: ## Start-up (bootstrap) and recent n8n logs
	kubectl -n $(NAMESPACE) logs deploy/$(RELEASE) -c bootstrap --tail=20
	kubectl -n $(NAMESPACE) logs deploy/$(RELEASE) -c n8n --tail=40

grafana: ## Open the EchoMind dashboard
	open http://localhost:3300/d/echomind-overview

n8n: ## Open the n8n editor
	open $(BASE_URL)

down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)
