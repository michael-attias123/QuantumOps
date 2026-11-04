# ADR 0002 — Always-on k3s on OCI Always Free, accessed via Tailscale

- **Status:** Accepted
- **Date:** 2026-11-04

## Context
Work happens from several computers, there is no local GPU, and the budget is $0. A laptop-hosted cluster only exists while that laptop is on. Managed control planes such as EKS cost about $73/month.

## Decision
Run k3s on two OCI Always Free Ampere A1 VMs (4 OCPU / 24 GB in total), provisioned by OpenTofu with no public inbound ports. Every computer reaches the cluster over Tailscale (free personal plan), and the Tailscale Kubernetes operator exposes the UIs. Vault auto-unseals with OCI KMS.

## Consequences
- The platform is always on and doesn't depend on any one laptop; the cluster is private by default.
- The cluster is ARM-only, so images are built for both arm64 and amd64.
- Risks: A1 capacity shortages and idle reclaim of Always Free VMs (see runbooks). Upgrading the account requires explicit approval.
