# ADR 0010 — OCI Free Trial credits are a disposable burst layer

- **Status:** Accepted
- **Date:** 2026-11-08
- **Relates to:** [ADR 0007](0007-zero-cost-policy.md) ($0 policy), [ADR 0008](0008-single-node-a1-cluster.md) (single A1 node)

## Context
A new Oracle Cloud account starts with a **Free Trial: $300 of credits, valid for 30 days**, on top of the Always Free
resources that never expire. Oracle's
[Free Tier page](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm) sets three rules:

1. Paid resources created with credits are **reclaimed when the trial ends**, unless the account is upgraded.
2. If the tenancy has **more than 2 OCPU / 12 GB of Ampere A1** when the trial ends, **all** A1 instances are disabled,
   then deleted after 30 days. Our permanent node would be lost with them.
3. During the trial the console shows *trial* limits, which are higher than the Always Free ones.

The trial started while the project is at P2. The GPU phases (P9 Kaggle remote GPU, P10 QEC decoders) are weeks away, so
the credits can't pay for a phase. They can buy **early answers** that would be expensive to get later.

## Decision
Treat trial credits as a **time-boxed burst layer that leaves nothing behind**:

- The permanent platform uses **only** Always Free shapes, sized to 2 OCPU / 12 GB from day 1 (ADR 0008). It never
  depends on a trial resource. `infra/oci/` validates A1 `ocpus <= 2` and `memory_gb <= 12`.
- Trial resources live in a **separate OpenTofu stack**, `infra/oci-trial/`, with its own state key
  (`trial/terraform.tfstate`). Every resource has the freeform tags `qops-trial=true` and `qops-expires=<date>`.
  The stack refuses to `apply` from 3 days before the trial end.
- **Hard stop on day 27.** `make trial-down` destroys the stack, and `make trial-audit` must then report zero tagged
  resources and A1 usage ≤ 2 OCPU / 12 GB (runbook `docs/runbooks/oci-trial-teardown.md`, added in P2).
- Budget alerts at **$50 / $150 / $250**. Never press *Upgrade* (ADR 0007: asking first is still required).

How the credits are spent, in priority order:

| # | Use | Cap |
|---|---|---|
| 1 | **GPU spike for L3.** A `VM.GPU.A10.1` (about $2/h, to be checked on the price list), started only for measuring sessions. It compares qiskit-aer-gpu with CPU Aer on our algorithms, and cudaq-qec (GPU) with PyMatching (CPU) on surface-code memory experiments for d = 3–9. It also checks that the GPU image planned for Kaggle builds and runs. Results go to `docs/reference/gpu-spike.md` and feed the P9/P10 decisions. | $150 |
| 2 | **2-node rehearsal.** A short-lived non-A1 x86 node (E4.Flex) used to practise a k3s join and a rebuild from Git and Vault. | $30 |
| 3 | **Reserve,** spent only if a phase finds a real need before day 27. Unspent credit costs nothing. | rest |

Not allowed: growing A1 beyond 2 OCPU / 12 GB because the trial permits it, paid managed services the platform would
come to rely on, and anything that must outlive day 27.

## Consequences
- The GPU risk for L3 is reduced weeks before P9, at no cash cost.
- If the GPU A10 limit stays at 0 (common on trial accounts), item 1 is dropped and nothing else changes.
- The trial stack adds one OpenTofu root and four make targets. After day 27 they stay as documentation of a closed
  experiment; they don't affect the permanent stack.
- Spending credits triggers the $1 Always Free budget alarm. That is expected during the trial. After the trial, any
  alarm means something is wrong.
