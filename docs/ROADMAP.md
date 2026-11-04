# QuantumOps — Delivery Roadmap

Build one phase at a time. A phase is **done** only when CI is green and every item in its *Definition of Done* is
checked, with each check scripted as `make verify-pN`. The design behind each item is in [ARCHITECTURE.md](ARCHITECTURE.md).

**Ground rules for every phase**
- **$0.** If a step would cost money, stop and ask first. Paid paths stay disabled by default.
- **GitOps.** If it runs in the cluster, it's declared in Git. The only imperative steps are `tofu apply` for the
  cluster and the Vault init/seed scripts.
- **No secrets in Git.** Secrets go through `make seed-secrets` → Vault, or as sensitive OpenTofu variables. gitleaks runs in CI.
- **Work from any computer.** Each machine needs only `git`, `uv`, `tailscale`, `kubectl` (plus `tofu` for P2). Nothing
  depends on one particular laptop.
- Each phase ends with updated docs (ADRs, runbooks) for whatever it introduced.

| # | Phase | Levels touched | Depends on | Status |
|---|---|---|---|---|
| P0 | Foundations | — | — | ☐ |
| P1 | L0 contract + local runtime | L0, L1, L3 (in-process) | P0 | ☐ |
| P2 | Cloud cluster (OCI Always Free + Tailscale) | platform | P0 | ☐ |
| P3 | GitOps bootstrap | platform | P2 | ☐ |
| P4 | Vault + ESO | platform | P3 | ☐ |
| P5 | State layer (Supabase) | platform | P4 | ☐ |
| P6 | Event-driven pipeline, one-shot (emulator) | L1, L2 | P1, P5 | ☐ |
| P7 | Real QPU providers + cost guard | L2 | P6 | ☐ |
| P8 | Iterative algorithms (VQE, QAOA) | L1, L2, L3 | P7 | ☐ |
| P9 | L3 error mitigation + remote GPU (Kaggle) | L3 | P8 | ☐ |
| P10 | L3 QEC experiments + decoders | L3 | P9 | ☐ |
| P11 | Observability | platform | P8 | ☐ |
| P12 | Hardening & supply chain | platform | P11 | ☐ |

---

## P0 — Foundations
**Goal:** a working repo and toolchain.

Build
- [ ] Monorepo skeleton matching [ARCHITECTURE §13](ARCHITECTURE.md#13-gitops-repository-layout-cicd)
- [ ] uv workspace (`packages/*`), Python 3.12, ruff, mypy, pytest, pre-commit
- [ ] `Makefile` with targets `lint`, `test`, `verify-p0`
- [ ] `docs/adr/` with the first ADRs: monorepo, OCI + Tailscale, Supabase, Git-manifest trigger, Sampler-everywhere,
      remote GPU via Kaggle, $0 policy
- [ ] Renovate config; `ci.yml` (lint + test + gitleaks) on amd64 **and** arm64 runners
- [ ] `infra/ci/kind-config.yaml` for later e2e tests

Definition of Done
- [ ] Fresh clone on any computer: `uv sync && make lint test` passes
- [ ] CI green on a PR (both architectures)

Cost: $0.

---

## P1 — L0 contract + local runtime (no Kubernetes)
**Goal:** researchers can write pure Qiskit and run the full loop in-process on any laptop.

Build
- [ ] `qops-core`: contract loader (`sampling`, `variational`, `qec-memory`), models, state serde (`state.json` + `schema_version`), QPY helpers
- [ ] `qops-providers`: provider interface + capability flags, synchronous `aer` provider
- [ ] `qops-stages`: SPSA ask/tell with JSON state; measurement grouping + expectation values from counts
- [ ] `qops-cli`: `qops run --local <path>`, `qops new algorithm <name> --kind …`
- [ ] Algorithms: `ghz_benchmark`, `vqe_h2`
- [ ] Version pin matrix for Qiskit 2.x + qiskit-aer + mthree + mitiq + qiskit-ionq + qiskit-braket-provider, tested on amd64 **and arm64**

Definition of Done
- [ ] GHZ run reports fidelity
- [ ] VQE-H2 (noiseless) reaches the exact energy within 1.6 mHa
- [ ] Interrupting and resuming from saved state reproduces an identical trajectory (seeded)
- [ ] Algorithms contain zero platform imports (checked by a lint rule)

Cost: $0.

---

## P2 — Cloud cluster (OCI Always Free + Tailscale)
**Goal:** an always-on, private, $0 cluster reachable from every computer.

Prerequisites (one-time, by you):
- Oracle Cloud account (a card is used for identity verification only; nothing is charged).
- Tailscale account (free personal plan).

Build
- [ ] `infra/oci/` (OpenTofu): VCN + subnet, security lists with **no public inbound**, 2× `VM.Standard.A1.Flex` (2 OCPU / 12 GB each)
- [ ] cloud-init: Tailscale join (auth key as a sensitive var), k3s server/agent bound to the tailnet IP, node labels `qops.io/pool`
- [ ] OCI KMS key (free) for later Vault auto-unseal
- [ ] Remote state in OCI Object Storage (S3 backend) + OpenTofu state encryption
- [ ] `make kubeconfig` (fetch kubeconfig over Tailscale), `make ssh-server`
- [ ] Runbook: A1 capacity errors, idle-reclaim policy, rebuilding the cluster from scratch

Definition of Done
- [ ] From a second computer: `tailscale up && make kubeconfig && kubectl get nodes` → 2 Ready arm64 nodes
- [ ] The VMs' public IPs answer on no port (checked from outside the tailnet)
- [ ] `tofu plan` shows no drift; the OCI cost report shows $0

Risks: A1 capacity (retry or try another availability domain), idle reclaim (a running cluster stays busy). · Cost: $0.

---

## P3 — GitOps bootstrap
**Goal:** one command installs the whole platform from Git.

Build
- [ ] `deploy/bootstrap/` (Argo CD Helm values + root Application) and `deploy/apps/` app-of-apps chart
- [ ] Sync waves and namespaces; Argo CD manages its own release
- [ ] Tailscale Kubernetes operator; Argo CD UI at `argocd.<tailnet>.ts.net`
- [ ] `deploy/envs/oci/` and `deploy/envs/ci/`
- [ ] `images.yml`: multi-arch build (native arm64 + amd64 runners) → GHCR → bot commits tags into `deploy/envs/oci`
- [ ] `infra/github/` (OpenTofu): branch protection, required checks
- [ ] `make bootstrap`

Definition of Done
- [ ] On a freshly rebuilt cluster, `make bootstrap` → all apps Synced/Healthy with no manual kubectl
- [ ] A Git change to a value shows up in the cluster
- [ ] An image built on `main` gets its tag bumped and deployed automatically
- [ ] The Argo CD UI opens from any tailnet computer and from nowhere else

Cost: $0.

---

## P4 — Vault + External Secrets
**Goal:** every credential comes from Vault; Vault config is GitOps; no laptop needed after a restart.

Build
- [ ] Vault (Raft standalone, injector, audit device) with **OCI KMS auto-unseal**
- [ ] `scripts/vault-init.sh`, `make seed-secrets`; recovery keys stored outside the repo; `make unseal` fallback
- [ ] vault-config-operator; policies, k8s auth roles, KV v2 mount declared as CRs
- [ ] ESO + ClusterSecretStore + ExternalSecrets for provider tokens (IBM, IonQ, Kaggle)
- [ ] ServiceAccounts `qops-l1`, `qops-l3`, `job-tracker` with distinct policies

Definition of Done
- [ ] Rebooting the server VM → Vault unseals itself
- [ ] Rotating the IBM token in Vault updates the K8s Secret within the refresh interval
- [ ] `qops-l3` is **denied** when reading QPU tokens; `qops-l1` is denied when reading the Kaggle key
- [ ] Vault audit log shows every access; gitleaks is clean

Spike: OCI KMS auto-unseal (fallback `make unseal` over Tailscale). · Cost: $0.

---

## P5 — State layer (Supabase)
**Goal:** durable state with short-lived DB credentials, plus a free offline twin for CI.

Build
- [ ] `infra/supabase/` (OpenTofu, state encryption): free project + settings
- [ ] `db/migrations/` (dbmate): `runs`, `iterations`, `remote_jobs`, `outbox`, `qpu_usage`, `gpu_usage`, `backend_cache`; RLS on, no policies
- [ ] Storage bucket `qops-artifacts`, signed-URL helpers, retention CronJob
- [ ] Argo CD PreSync migration Job (`qops-migrator` creds)
- [ ] Vault DB secrets engine via the Supavisor pooler: `qops-worker`, `qops-tracker`, `qops-migrator`, `qops-grafana-ro`
- [ ] `qops-core.store` (Postgres + S3) with conditional state-transition helpers
- [ ] `ci` overlay: in-cluster Postgres + MinIO

Definition of Done
- [ ] A pod receives 1h dynamic creds; the role disappears after the TTL
- [ ] Hydrate/dehydrate round-trip tests pass against Supabase **and** the CI overlay
- [ ] Concurrent claim test: exactly one of N workers wins a transition

Spike: dynamic roles through Supavisor (`role.projectref`); fallback Vault static rotated roles. · Cost: $0.

---

## P6 — Event-driven pipeline, one-shot (emulator)
**Goal:** Git commit → QPU job → results, with zero pods while waiting.

Build
- [ ] `qops-emulator`: async REST fake QPU with Aer, fake-backend noise, queue-delay distribution and failure injection
- [ ] Images `qops-runtime`, `qops-tracker`, `qops-emulator` (multi-arch)
- [ ] Argo Workflows + Argo Events (NATS JetStream EventBus) via Argo CD
- [ ] `QuantumExperiment` CRD (status subresource, printer columns)
- [ ] EventSources: resource (CRD) + webhook (tracker); Sensors: start, job-ready, job-failed, cancel
- [ ] WorkflowTemplates: `qops-run`, `qops-iteration`, `handle-failure`, `cancel-run` (git input artifact, Vault Agent init-only)
- [ ] `job-tracker`: `FOR UPDATE SKIP LOCKED` polling, adaptive backoff, result fetch → Storage, outbox dispatcher, `/metrics`
- [ ] CLI: `qops run --cluster`, `qops status`, `qops logs` (work from any tailnet computer)
- [ ] `experiments/ghz-emulator.yaml`; `e2e.yml` on kind

Definition of Done
- [ ] Committing `experiments/ghz-emulator.yaml` → run `SUCCEEDED`, CR status updated
- [ ] **Zero `qops-runs` pods during the emulated queue wait**
- [ ] A duplicate webhook is a no-op; killing the tracker mid-wait still completes the run
- [ ] `e2e.yml` runs this scenario on kind in CI

Cost: $0.

---

## P7 — Real QPU providers + cost guard
**Goal:** the same pipeline on real hardware, with spend provably $0.

Build
- [ ] `ibm` provider (SamplerV2, job/batch mode), `ionq` (cloud simulator), `braket` (local simulator; paid devices flagged)
- [ ] Target/calibration cache (`backend_cache`)
- [ ] `qpu_usage` tracking from job metrics
- [ ] Cost guard (USD > 0 needs `allowPaid` **and** Vault `paid_enabled`; IBM 80% monthly cap; run `maxQpuSeconds`)
- [ ] Failure/resubmit flow with attempt limits
- [ ] Provider contract tests with recorded fixtures (no live calls in CI)

Definition of Done
- [ ] GHZ on **real IBM hardware** (a few QPU-seconds) and on the IonQ simulator → SUCCEEDED
- [ ] A paid-device experiment is rejected with a clear reason
- [ ] Usage is recorded and visible per month

Cost: $0.

---

## P8 — Iterative algorithms (VQE, QAOA)
**Goal:** the multi-round CPU → QPU → L3 → CPU loop.

Build
- [ ] Variational loop across workflows: ask on L1, tell on L3, state persisted every iteration
- [ ] `vqe_h2`, `qaoa_maxcut` algorithms + experiments
- [ ] Budgets (`maxIterations`, `maxQpuSeconds`) → `BUDGET_EXCEEDED`
- [ ] Cancel via `suspend: true` or CR deletion → provider cancel
- [ ] CR status: iteration, best value, QPU seconds

Definition of Done
- [ ] VQE runs ≥ 30 iterations on the emulator with 0 pods between iterations
- [ ] One small VQE on IBM stays under 120 QPU-seconds
- [ ] Cancel stops the provider job and marks the run CANCELLED

Cost: $0.

---

## P9 — L3: error mitigation + remote GPU (Kaggle)
**Goal:** pluggable mitigation, and GPU compute used through an API exactly like the QPU.

Prerequisite (one-time, by you): a Kaggle account with phone verification (needed for GPU access) and an API token.

Build
- [ ] Stage plugin system (`prepare()` in L1, `apply()` in L3; entry points)
- [ ] `m3`, `zne` (Mitiq folding + extrapolation), `cdr`
- [ ] Remote-GPU adapter `qops_providers.gpu` (same interface as the QPU adapter) with `kaggle` and `local-cpu` implementations
- [ ] `kaggle/` kernel template: installs `qops-stages` at the pinned SHA, reads input and writes output only through signed URLs
- [ ] job-tracker generalized to `remote_jobs.kind = gpu`; `gpu-job-ready` / `gpu-job-failed` events; `GPU_*` iteration states
- [ ] `gpu_usage` weekly quota guard (refuse at ≥ 80%, `auto` falls back to CPU); `accelerator: cpu | remote-gpu | auto` routing with size thresholds
- [ ] Kaggle API key in Vault, readable only by `qops-l3` and `job-tracker`

Definition of Done
- [ ] On the noisy emulator, ZNE+M3 reduces VQE energy error vs unmitigated
- [ ] The same CDR run via `cpu` and `remote-gpu` matches within tolerance
- [ ] **Zero pods during the Kaggle GPU wait**; the remote job holds no DB, Vault or QPU credentials
- [ ] Exceeding the GPU quota guard falls back to CPU automatically

Cost: $0 (Kaggle free quota, enforced by the guard).

---

## P10 — L3: QEC experiments + decoders
**Goal:** error-correction experiments decoded on CPU and on the remote GPU.

Build
- [ ] `qec_repetition` (d = 3/5/7) and `qec_surface` (rotated d = 3, emulator)
- [ ] Stim circuit + detector error model from the same spec, with noise from backend calibration
- [ ] Decoders: `pymatching` (CPU, default), `ldpc` BP+OSD (CPU), `cudaq-qec` (remote GPU via Kaggle)
- [ ] Batch decoding benchmark (shots/s cluster CPU vs Kaggle GPU, including startup overhead)

Definition of Done
- [ ] Logical error rate decreases with distance on the emulator (below threshold)
- [ ] GPU and CPU decoders agree within statistical error; benchmark published in docs
- [ ] One repetition-code run on real IBM hardware

Cost: $0.

---

## P11 — Observability
**Goal:** see platform health, queue behavior, science results and cost in one place.

Build
- [ ] kube-prometheus-stack (short retention), Loki (filesystem) + Alloy via Argo CD, sized for the 24 GB cluster
- [ ] Tracker metrics, Argo Workflows custom metrics, Grafana → Supabase (read-only role); Grafana via Tailscale
- [ ] Dashboards as code: Platform (zero-idle KPI), Remote jobs (QPU + GPU waits, IBM and Kaggle quotas), Science, Cost
- [ ] Alerts: IBM/Kaggle quota ≥ 80%, READY-not-dispatched > 10 min, workflow failures, Vault sealed, Supabase unreachable, node NotReady

Definition of Done
- [ ] A full VQE run is visible end-to-end (convergence, queue waits, zero-idle KPI, quotas)
- [ ] A forced test fires an alert

Cost: $0.

---

## P12 — Hardening & supply chain
**Goal:** production-grade guardrails.

Build
- [ ] Kyverno: PSS restricted, registry allowlist, required limits, cosign keyless `verifyImages`, **paid-provider gate**
- [ ] Default-deny NetworkPolicies (L1 → Vault/Supabase/QPU APIs; L3 → Vault/Supabase/Kaggle)
- [ ] Review of OCI security lists and Tailscale ACLs
- [ ] Argo CD AppProjects / RBAC
- [ ] CI: SBOM (syft) + cosign keyless signing + Trivy gate
- [ ] Vault raft snapshot CronJob → OCI Object Storage; runbooks: Vault sealed, emulator down, Supabase paused, VM reclaimed, Kaggle quota exhausted

Definition of Done
- [ ] Unsigned images and paid experiments are both rejected at admission
- [ ] Every chaos scenario recovers by following its runbook, including a full cluster rebuild from Git + Vault snapshot

Cost: $0.

---

## Later, only with your approval
- A dedicated GPU node (paid cloud GPU, or a GPU machine joined over Tailscale). The scheduling labels are already in place.
- Paid QPU devices (IBM pay-as-you-go, IonQ / Braket hardware).

## Final acceptance
- [ ] Four committed experiments (GHZ on IBM, VQE on emulator with ZNE, QAOA on IonQ simulator, QEC repetition on
      emulator with Kaggle GPU decoding) all reach `SUCCEEDED` with no manual steps
- [ ] The zero-idle KPI shows no compute pods during QPU or GPU waits
- [ ] Paid spend = **$0**
