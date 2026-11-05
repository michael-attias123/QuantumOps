# Architecture Decision Records

Short records of significant decisions. A new ADR copies the template below, takes the next number, and is never
rewritten after acceptance; supersede it with a new ADR instead.

| ADR | Decision |
|---|---|
| [0001](0001-monorepo-uv-workspace.md) | Monorepo with a uv workspace |
| [0002](0002-oci-always-free-and-tailscale.md) | Always-on k3s on OCI Always Free, accessed via Tailscale |
| [0003](0003-supabase-behind-interfaces.md) | Supabase as state store, behind Postgres + S3 interfaces |
| [0004](0004-git-manifest-trigger.md) | Experiments are Git-committed QuantumExperiment resources |
| [0005](0005-sampler-everywhere.md) | Sampler primitive everywhere; expectation values computed in L3 |
| [0006](0006-remote-gpu-via-kaggle.md) | Remote GPU via the Kaggle API, used like a QPU |
| [0007](0007-zero-cost-policy.md) | $0 policy with two-gate paid paths |
| [0008](0008-single-node-a1-cluster.md) | Single-node cluster on the reduced A1 allowance (amends 0002) |

## Template

```markdown
# ADR NNNN — Title

- **Status:** Proposed | Accepted | Superseded by NNNN
- **Date:** YYYY-MM-DD

## Context
## Decision
## Consequences
```
