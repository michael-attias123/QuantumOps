# ADR 0008 — Single-node cluster on the reduced A1 allowance

- **Status:** Accepted
- **Date:** 2026-11-05
- **Amends:** [ADR 0002](0002-oci-always-free-and-tailscale.md) (sizing only)

## Context
ADR 0002 assumed Always Free Ampere A1 = 4 OCPU / 24 GB, split over two VMs. Public reports
([InfoQ](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/),
[heise](https://www.heise.de/en/news/Oracle-halves-free-cloud-resources-11334516.html)) say Oracle reduced it in mid-2026
to 1,500 OCPU-hours and 9,000 GB-hours a month, i.e. **2 OCPU / 12 GB** in total. Two VMs would then be 1 OCPU / 6 GB each,
and the platform components alone would fill most of one.

## Decision
Run **one** `VM.Standard.A1.Flex` with 2 OCPU / 12 GB as a single-node k3s cluster. Trim the stack: one replica per
component, explicit requests/limits, short Prometheus retention, Loki optional, Traefik/servicelb disabled (the
Tailscale operator exposes services), and capped workflow parallelism. Compute pods keep selecting
`qops.io/pool=cpu`, so nodes can be added later without chart changes.

## Consequences
- Simpler: no inter-node networking, one machine to rebuild.
- No node redundancy: a VM reboot is a full outage, recovered by Git (Argo CD) and Vault snapshots (P12 runbooks).
- Memory is the binding constraint. Each phase must check that the node stays under ~80% memory, and P11 adds an alert.
- The user confirms the actual limits on the console's *Limits, Quotas and Usage* page; if the account shows more, this
  ADR can be revisited.
