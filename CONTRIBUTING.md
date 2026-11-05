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
| `make sync` | install the workspace from `uv.lock` |
| `make lint` | ruff check, ruff format check, mypy (strict), yamllint |
| `make fmt` | auto-fix and format |
| `make test` | pytest (all packages + architecture guards) |
| `make compat` | version pin matrix (installs the `compat` group) |
| `make verify-pN` | Definition-of-Done checks for phase N |

## Rules
- **Algorithms stay pure Qiskit:** nothing under `algorithms/` may import `qops_*`. `tests/test_architecture.py` enforces this.
- **Layering:** `qops_core` imports no other `qops_*` package.
- **No secrets in Git:** they go to Vault (`make seed-secrets`, from P4). gitleaks runs in pre-commit and CI.
- **$0:** anything that could cost money needs explicit approval first (ADR 0007).
- **Dependencies:** add them with `uv add --package <pkg> <dep>` and commit `uv.lock`.

## Branches & commits
- **One branch per phase:** `phase/pN-<slug>` (e.g. `phase/p2-cloud-cluster`), branched from the previous phase's branch,
  or from `main` once that phase is merged. One PR per phase into `main`. CI must be green (amd64 + arm64, pin matrix,
  secret scan).
- Smaller changes inside a phase go on short-lived branches off the phase branch.
- Commit messages: `<area>: <imperative summary>` (e.g. `providers: add IBM SamplerV2 adapter`).
- Significant decisions get an ADR in `docs/adr/`.
