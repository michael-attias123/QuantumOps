# ADR 0004 — Experiments are Git-committed QuantumExperiment resources

- **Status:** Accepted
- **Date:** 2026-11-04

## Context
'GitOps for everything' should include experiment runs. Argo CD cannot trigger workflows cleanly, and the private cluster accepts no inbound webhooks.

## Decision
Experiments are `QuantumExperiment` custom resources in `experiments/`, synced by Argo CD. Argo Events' resource EventSource watches the CRD and starts Argo Workflows, so no custom controller is needed. A `qops` CLI submits ad-hoc dev runs into a namespace Argo CD doesn't manage.

## Consequences
- Every official run is auditable through a Git commit and reproducible from its pinned SHA.
- Re-runs need a `runRevision` bump; deleting the file cancels the run.
