# ADR 0001 — Monorepo with a uv workspace

- **Status:** Accepted
- **Date:** 2026-11-04

## Context
Platform code, researcher algorithms, GitOps manifests, infrastructure and experiments change together. Splitting them across repositories would mean coordinating versions and permissions for a single-person team.

## Decision
One public monorepo. Python lives in a uv workspace (`packages/*`, Python 3.12) with one lockfile (`uv.lock`), shared ruff/mypy/pytest config in the root `pyproject.toml`, and import-layering rules enforced by `tests/test_architecture.py`.

## Consequences
- One clone and one `make verify-p0` reproduces everything on any computer.
- CI bot commits (image tags) land in the same repo. Commits made with GITHUB_TOKEN do not retrigger workflows, which prevents loops.
- Package boundaries are enforced by tests, not by repository boundaries.
