# ADR 0009 — Repository layout and branch lifecycle

- **Status:** Accepted
- **Date:** 2026-11-05

## Context
After P0/P1 the root held 11 folders (6 of them empty placeholders) and 8 loose config files, and merged phase
branches stayed in the branch list. Eleven more phases will add infrastructure, manifests, images, migrations and
runbooks.

## Decision
- **Researcher-facing code under `research/`** (`algorithms/`, `experiments/`).
- **Folders appear just in time**: created by the phase that fills them, with no `.gitkeep` placeholders. The planned
  layout, with the creating phase for each path, lives in ARCHITECTURE §13.
- **Things live with their owner**: Dockerfiles in the package they build, DB migrations in `qops-core` (which owns the
  store), the Kaggle kernel template in `qops-providers`, bootstrap scripts under `deploy/bootstrap/scripts/`.
- **Root stays small**: tool configs that can move do (`.github/CONTRIBUTING.md`, `.github/renovate.json`,
  `.github/linters/`). Make targets live in `make/<area>.mk`, and local caches in `.cache/`.
- **Branch lifecycle**: `phase/pN-<slug>` from `main` → PR → merge commit → annotated tag `pN-<slug>` on the merge →
  delete the branch. Work between phases uses `chore/<slug>` with the same flow and no tag.

## Consequences
- The root shows 8 folders and stays that size; each phase knows where its files go.
- Paths are longer for researchers (`research/algorithms/...`).
- Phase history is preserved by tags rather than branches.
