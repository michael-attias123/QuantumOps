# ADR 0007 — $0 policy with two-gate paid paths

- **Status:** Accepted
- **Date:** 2026-11-04

## Context
The project must cost nothing. Some providers offer paid devices next to free ones.

## Decision
Every component uses OSS or a free tier. Paid paths (QPU hardware beyond free plans, managed simulators, cloud GPUs, account upgrades) are denied by default at two independent gates: a Kyverno admission policy and a runtime cost guard. The guard requires both `budget.allowPaid` and Vault `paid_enabled`. Quota guards stop at 80% of free allowances.

## Consequences
- Spend is provably $0, and any paid step needs explicit approval.
- Some capabilities (sessions on IBM, cloud GPUs in-cluster) stay out of scope unless approved.
