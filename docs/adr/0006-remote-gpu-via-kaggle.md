# ADR 0006 — Remote GPU via the Kaggle API, used like a QPU

- **Status:** Accepted
- **Date:** 2026-11-04

## Context
L3 benefits from a GPU for batch QEC decoding and large simulations. There is no local GPU, and no free cloud GPU attaches to Kubernetes.

## Decision
Treat the GPU as a remote accelerator provider with the same interface as the QPU adapter. L3 pushes a Kaggle kernel and exits. The job tracker polls it, fetches the output into Storage, and resumes the workflow. The kernel installs `qops-stages` at the pinned SHA and uses only signed URLs, never credentials. A weekly quota guard (80%) falls back to CPU, and every GPU stage has a CPU path.

## Consequences
- $0 GPU access with zero idle pods while the GPU job runs.
- 1–2 minutes of startup latency, so only heavy stages are routed there.
- Kaggle requires a phone-verified account for GPU access.
