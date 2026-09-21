# kubeflow-lab
#
#   make doctor          check this machine can actually run the tier you want
#   make up TIER=0       boot the cluster and install Kubeflow
#   make status          what is running, what is stuck
#   make forward         port-forward the UI
#   make sh              shell into the pinned toolbox container
#   make down            destroy the cluster (keeps images cached)
#   make nuke            destroy the cluster AND the image cache
#
# TIER 0 (~4GB)  Pipelines standalone. No Istio, no Dex, no login.
# TIER 1 (~10GB) Community Distribution minus serving. Istio, Dex, Profiles,
#                Notebooks, Katib. This is where the cloud-eng content lives.
# TIER 2 (~16GB) Everything, including KServe + Knative.

SHELL := /bin/bash
.DEFAULT_GOAL := help

TIER ?= 0
ROOT := $(shell pwd)

export TIER
export ROOT

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Current TIER=$(TIER)  (override with: make up TIER=1)"

.PHONY: doctor
doctor: ## Preflight: Docker, RAM, disk, WSL2 config, inotify limits
	@bash scripts/doctor.sh

.PHONY: tools
tools: ## Build the pinned toolbox image
	@bash scripts/tools.sh build

.PHONY: sh
sh: tools ## Interactive shell inside the toolbox (kubectl, kustomize, kind, k9s)
	@bash scripts/tools.sh shell

.PHONY: up
up: ## Create the cluster and install Kubeflow at $(TIER)
	@bash scripts/up.sh

.PHONY: down
down: ## Delete the kind cluster
	@bash scripts/down.sh

.PHONY: nuke
nuke: ## Delete the cluster and the cached images
	@bash scripts/down.sh --nuke

.PHONY: status
status: ## Show cluster / Kubeflow health, and anything not Running
	@bash scripts/status.sh

.PHONY: forward
forward: ## Port-forward the appropriate UI for this tier
	@bash scripts/forward.sh

.PHONY: creds
creds: ## Print the default login (tier 1+)
	@bash scripts/creds.sh

.PHONY: freeze
freeze: ## Resolve floating tool versions into VERSIONS.lock
	@bash scripts/tools.sh freeze

.PHONY: lint
lint: ## shellcheck + yaml lint, no cluster needed
	@bash scripts/lint.sh

.PHONY: labs
labs: ## List the labs and their prerequisite tier
	@bash scripts/labs.sh
