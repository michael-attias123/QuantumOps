# P0 — Foundations: overview

**Status:** ✅ done · **Commit:** `03be2e0` · **CI:** [run #1](https://github.com/michael-attias123/QuantumOps/actions/runs/41847753135) green
(lint & test on amd64 + arm64, secret scan) · **Cost:** $0

## Goal
A repo and toolchain that work the same from any computer, which every later phase builds on.

## What was built
- **uv workspace** (Python 3.12, one `uv.lock`) with seven packages: `qops-core`, `-providers`, `-stages`, `-runtime`,
  `-tracker`, `-emulator`, `-cli`. They were empty shells in P0 with the intended dependency layering wired in.
- **Architecture guards** (`tests/test_architecture.py`): `research/algorithms/` may not import platform code, and `qops_core`
  may not import other platform packages.
- **Tooling:** `make sync|lint|fmt|test|verify-p0`, ruff, strict mypy, yamllint, pre-commit (with gitleaks), `.editorconfig`,
  and a `.gitignore` that keeps kubeconfigs, keys and OpenTofu state out of Git.
- **CI** (`.github/workflows/ci.yml`): lint + tests on **amd64 and arm64** runners, plus a gitleaks secret scan.
- **Renovate** config for weekly dependency PRs. It only starts working once the free Renovate GitHub App is installed.
- **Skeleton folders** for later phases (`deploy/`, `infra/`, `kaggle/`, `db/`, `images/`, `scripts/`; the empty ones were removed
  in the repo tidy-up, see [ADR 0009](../adr/0009-repository-layout-and-branches.md)) and a kind
  cluster config for the P6 end-to-end tests.
- **Decision records** `docs/adr/0001–0007`, plus `CONTRIBUTING.md` (now `.github/CONTRIBUTING.md`) and a README quickstart with a CI badge.

## Definition of Done
| Check | Evidence |
|---|---|
| Fresh clone → `uv sync && make lint test` passes | verified from a fresh clone |
| CI green on both architectures | CI run #1 |

## Decisions and notes
- Pre-commit runs ruff/mypy from the locked environment, so local hooks and CI can't drift apart.
- No license set yet; that's your choice.
