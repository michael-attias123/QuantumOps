# Contributing

## Setup (any computer)
Requirements: `git` and [uv](https://docs.astral.sh/uv/). uv installs Python 3.12 automatically.

```bash
git clone https://github.com/michael-attias123/QuantumOps.git && cd QuantumOps
make verify-p0          # sync + lint + test
uv run pre-commit install
```

## Make targets
| Target | What it does |
|---|---|
| `make help` | list every target |
| `make sync` | install the workspace from `uv.lock` |
| `make lint` | ruff check, ruff format check, mypy (strict), yamllint |
| `make fmt` | auto-fix and format |
| `make test` | pytest (all packages + architecture guards) |
| `make compat` | version pin matrix (installs the `compat` group) |
| `make verify-pN` | Definition-of-Done checks for phase N |

## Rules
- **Algorithms stay pure Qiskit:** nothing under `research/algorithms/` may import `qops_*`. `tests/test_architecture.py` enforces this.
- **Layering:** `qops_core` imports no other `qops_*` package.
- **No secrets in Git:** they go to Vault (`make seed-secrets`, from P4). gitleaks runs in pre-commit and CI.
- **$0:** anything that could cost money needs explicit approval first (ADR 0007).
- **Dependencies:** add them with `uv add --package <pkg> <dep>` and commit `uv.lock`.

## Branches & commits
- **One branch per phase:** `phase/pN-<slug>` (e.g. `phase/p2-cloud-cluster`) from `main` → PR → merge commit →
  annotated tag `pN-<slug>` on the merge → delete the branch. CI must be green (amd64 + arm64, pin matrix, secret scan).
- Work between phases: `chore/<slug>`, same flow, no tag.

## Where files go ([ADR 0009](../docs/adr/0009-repository-layout-and-branches.md))
- Create a folder only when you add real files to it; no `.gitkeep` placeholders.
- Researcher code: `research/algorithms/`; run requests: `research/experiments/`.
- New make targets: a `make/<area>.mk` file, never the root `Makefile`.
- Dockerfiles live in the package they build; migrations in `packages/qops-core/migrations/`.
- Planned paths for every phase: ARCHITECTURE §13.
- Commit messages: `<area>: <imperative summary>` (e.g. `providers: add IBM SamplerV2 adapter`).
- Significant decisions get an ADR in `docs/adr/`.
