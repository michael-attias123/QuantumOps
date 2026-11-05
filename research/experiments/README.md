# research/experiments/ — GitOps run requests

Each file is a `QuantumExperiment` custom resource (`qops.io/v1alpha1`). Merging a file to `main` starts a run:
Argo CD syncs it, and Argo Events starts the workflow. Bump `spec.runRevision` to re-run an experiment, or delete the file to cancel it.
See [ARCHITECTURE §7](../../docs/ARCHITECTURE.md#7-trigger--the-quantumexperiment-crd). The first experiment arrives in P6.
