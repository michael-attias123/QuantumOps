# QuantumOps — targets live in make/*.mk (one file per area; add new areas there, not here).
.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
UV ?= uv

include make/*.mk

.PHONY: help
help: ## Show available targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
