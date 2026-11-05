.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
UV ?= uv

.PHONY: help sync lint fmt test verify-p0 clean

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

sync: ## Install the workspace and dev tools (uses uv.lock)
	$(UV) sync --locked

lint: ## Ruff lint + format check, mypy (strict), yamllint
	$(UV) run ruff check .
	$(UV) run ruff format --check .
	$(UV) run mypy
	$(UV) run yamllint --strict .

fmt: ## Auto-fix lint issues and format code
	$(UV) run ruff check --fix .
	$(UV) run ruff format .

test: ## Run all tests
	$(UV) run pytest

verify-p0: sync lint test ## P0 Definition of Done checks
	$(UV) run qops --version
	@echo "P0 verified"

clean: ## Remove caches and build outputs
	rm -rf .venv .mypy_cache .pytest_cache .ruff_cache dist build
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
