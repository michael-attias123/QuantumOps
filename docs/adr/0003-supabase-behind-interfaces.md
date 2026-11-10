# ADR 0003 — Supabase as state store, behind Postgres + S3 interfaces

- **Status:** Accepted
- **Date:** 2026-11-04

## Context
Execution state must survive between ephemeral pods and needs to be queryable. Supabase Free offers managed Postgres (500 MB) and storage (1 GB) at $0.

## Decision
Use Supabase via the Supavisor pooler (IPv4, session mode) and its S3-compatible Storage. Platform code depends only on 'Postgres + S3'. CI and offline development use in-cluster Postgres + SeaweedFS. RLS is enabled with no policies, and access goes only through Vault-issued Postgres roles.

## Consequences
- CI never touches the real project, and the vendor is replaceable.
- Free-tier quotas need a retention job, and the auto-pause after 7 idle days needs an alert and a runbook.

## Update (P5 planning, 2026-11-10)
- **CI object store:** SeaweedFS instead of MinIO, which stopped publishing images in October 2025 and was archived in
  April 2026. Code only talks S3, so nothing else changes.
- **Vault-issued roles:** Vault is now the shared one ([ADR 0013](0013-shared-vault.md)), so its database mount is
  declared in shared-platform. A local spike first checks dynamic roles through Supavisor (`<role>.<project-ref>`);
  static rotated roles are the fallback.
- **Ownership:** objects belong to `qops_owner` (NOLOGIN), so an expired migrator login never leaves a table without
  an owner.
