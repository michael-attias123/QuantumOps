# Day-to-day development targets.
YAMLLINT_CONFIG := .github/linters/yamllint.yml

.PHONY: sync lint fmt test compat clean

sync: ## Install the workspace and dev tools (uses uv.lock)
	$(UV) sync --locked

lint: ## Ruff lint + format check, mypy (strict), yamllint, shellcheck
	$(UV) run ruff check .
	$(UV) run ruff format --check .
	$(UV) run mypy
	$(UV) run yamllint -c $(YAMLLINT_CONFIG) --strict .
	$(UV) run shellcheck -x -P SCRIPTDIR infra/bootstrap/*.sh infra/scripts/*.sh

fmt: ## Auto-fix lint issues and format code
	$(UV) run ruff check --fix .
	$(UV) run ruff format .

test: ## Run all tests
	$(UV) run pytest

compat: ## Version pin matrix: Qiskit 2.x with mthree, mitiq and provider SDKs
	$(UV) run --group compat pytest -q tests/test_compat_matrix.py

clean: ## Remove caches and build outputs
	rm -rf .venv .cache dist build
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
