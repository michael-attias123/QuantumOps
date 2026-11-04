# QuantumOps — Delivery Roadmap

Build one phase at a time. A phase is **done** only when CI is green and every item in its *Definition of Done* is
checked, with each check scripted as `make verify-pN`. The design behind each item is in [ARCHITECTURE.md](ARCHITECTURE.md).

**Ground rules for every phase**
- **$0.** If a step would cost money, stop and ask first. Paid paths stay disabled by default.
- **GitOps.** If it runs in the cluster, it's declared in Git. The only imperative steps are cluster creation and the Vault
  init/unseal/seed scripts.
- **No secrets in Git.** Secrets go through `make seed-secrets` → Vault. gitleaks runs in CI.
- Each phase ends with updated docs (ADRs, runbooks) for whatever it introduced.

| # | Phase | Levels touched | Depends on | Status |
|---|---|---|---|---|
| P0 | Foundations | — | — | ☐ |
| P1 | L0 contract + local runtime | L0, L1, L3 (in-process) | P0 | ☐ |
| P2 | GitOps bootstrap | platform | P0 | ☐ |
| P3 | Vault + ESO | platform | P2 | ☐ |
| P4 | State layer (Supabase) | platform | P3 | ☐ |
| P5 | Event-driven pipeline, one-shot (emulator) | L1, L2 | P1, P4 | ☐ |
| P6 | Real QPU providers + cost guard | L2 | P5 | ☐ |
| P7 | Iterative algorithms (VQE, QAOA) | L1, L2, L3 | P6 | ☐ |
| P8 | L3 error mitigation + GPU | L3 | P7 | ☐ |
| P9 | L3 QEC experiments + decoders | L3 | P8 | ☐ |
| P10 | Observability | platform | P7 | ☐ |
| P11 | Hardening & supply chain | platform | P10 | ☐ |
| P12 | Cloud phase (provider TBD) | platform | P11 | ☐ |

---

## P0 — Foundations
**Goal:** a working repo, toolchain and local GPU-enabled cluster.

Build
- [ ] Monorepo skeleton matching [ARCHITECTURE §13](ARCHITECTURE.md#13-gitops-repository-layout-cicd)
- [ ] uv workspace (`packages/*`), Python 3.12, ruff, mypy, pytest, pre-commit
- [ ] `Makefile` with targets `cluster-up`, `cluster-down`, `lint`, `test`, `verify-p0`
- [ ] `docs/adr/` with the first ADRs: monorepo, k3d, Supabase, Git-manifest trigger, Sampler-everywhere, $0 policy
- [ ] Renovate config; `ci.yml` (lint + test + gitleaks)
- [ ] `infra/local/k3d-config.yaml`: server + `system`/`cpu`/`gpu` agents with labels and taints
- [ ] `infra/local/k3s-cuda/` image (NVIDIA container toolkit) and NVIDIA device plugin smoke manifest

Definition of Done
- [ ] `make cluster-up` → 4 nodes with correct labels and taints
- [ ] A pod on the `gpu` node runs `nvidia-smi` successfully
- [ ] CI green on a PR

Spike: k3d GPU passthrough on WSL2 (fallback: nvkind). · Cost: $0.

---

## P1 — L0 contract + local runtime (no Kubernetes)
**Goal:** researchers can write pure Qiskit and run the full loop in-process.

Build
- [ ] `qops-core`: contract loader (`sampling`, `variational`, `qec-memory`), models, state serde (`state.json` + `schema_version`), QPY helpers
- [ ] `qops-providers`: provider interface + capability flags, synchronous `aer` provider
- [ ] `qops-stages`: SPSA ask/tell with JSON state; measurement grouping + expectation values from counts
- [ ] `qops-cli`: `qops run --local <path>`, `qops new algorithm <name> --kind …`
- [ ] Algorithms: `ghz_benchmark`, `vqe_h2`
- [ ] Version pin matrix for Qiskit 2.x + qiskit-aer + mthree + mitiq + qiskit-ionq + qiskit-braket-provider

Definition of Done
- [ ] GHZ run reports fidelity
- [ ] VQE-H2 (noiseless) reaches the exact energy within 1.6 mHa
- [ ] Interrupting and resuming from saved state reproduces an identical trajectory (seeded)
- [ ] Algorithms contain zero platform imports (checked by a lint rule)

Cost: $0.

---

## P2 — GitOps bootstrap
**Goal:** one command rebuilds the whole platform from Git.

Build
- [ ] `deploy/bootstrap/` (Argo CD Helm values + root Application) and `deploy/apps/` app-of-apps chart
- [ ] Sync waves and namespaces; Argo CD manages its own release
- [ ] `deploy/envs/local/`; Traefik ingress for `argocd.qops.localhost`
- [ ] `images.yml`: buildx → GHCR → bot commits tags into `deploy/envs/local`
- [ ] `infra/github/` (OpenTofu): branch protection, required checks
- [ ] `make bootstrap`

Definition of Done
- [ ] `make cluster-down && make cluster-up && make bootstrap` → all apps Synced/Healthy with no manual kubectl
- [ ] A Git change to a value shows up in the cluster
- [ ] An image built on `main` gets its tag bumped and deployed automatically

Cost: $0 (public repo → free Actions and GHCR).

---

## P3 — Vault + External Secrets
**Goal:** every credential comes from Vault; Vault config is GitOps.

Build
- [ ] Vault (Raft standalone, injector, audit device) via Argo CD
- [ ] `scripts/vault-init.sh`, `make unseal`, `make seed-secrets` (keys kept in `~/.qops/`, never in the repo)
- [ ] vault-config-operator; policies, k8s auth roles, KV v2 mount declared as CRs
- [ ] ESO + ClusterSecretStore + ExternalSecrets for provider tokens
- [ ] ServiceAccounts `qops-runtime-cpu`, `qops-runtime-gpu`, `qops-tracker` with distinct policies

Definition of Done
- [ ] Rotating the IBM token in Vault updates the K8s Secret within the refresh interval
- [ ] `qops-runtime-gpu` is **denied** when reading `kv/qops/providers/*`
- [ ] Vault audit log shows every access; gitleaks is clean

Cost: $0.

---

## P4 — State layer (Supabase)
**Goal:** durable state with short-lived DB credentials, plus a free offline twin for CI.

Build
- [ ] `infra/supabase/` (OpenTofu, state encryption): free project + settings
- [ ] `db/migrations/` (dbmate): `runs`, `iterations`, `qpu_jobs`, `outbox`, `qpu_usage`, `backend_cache`; RLS on, no policies
- [ ] Storage bucket `qops-artifacts` and retention CronJob
- [ ] Argo CD PreSync migration Job (`qops-migrator` creds)
- [ ] Vault DB secrets engine via the Supavisor pooler: `qops-worker`, `qops-tracker`, `qops-migrator`, `qops-grafana-ro`
- [ ] `qops-core.store` (Postgres + S3) with conditional state-transition helpers
- [ ] `deploy/envs/ci/` overlay: in-cluster Postgres + MinIO

Definition of Done
- [ ] A pod receives 1h dynamic creds; the role disappears after the TTL
- [ ] Hydrate/dehydrate round-trip tests pass against Supabase **and** the CI overlay
- [ ] Concurrent claim test: exactly one of N workers wins a transition

Spike: dynamic roles through Supavisor (`role.projectref` usernames); fallback Vault static rotated roles. · Cost: $0 (Supabase Free).

---

## P5 — Event-driven pipeline, one-shot (emulator)
**Goal:** Git commit → QPU job → results, with zero pods while waiting.

Build
- [ ] `qops-emulator`: async REST fake QPU with Aer, fake-backend noise, queue-delay distribution and failure injection
- [ ] `images/runtime-cpu`, `images/tracker`, `images/emulator`
- [ ] Argo Workflows + Argo Events (NATS JetStream EventBus) via Argo CD
- [ ] `QuantumExperiment` CRD (status subresource, printer columns)
- [ ] EventSources: resource (CRD) + webhook (tracker); Sensors: start, job-ready, job-failed, cancel
- [ ] WorkflowTemplates: `qops-run`, `qops-iteration`, `handle-failure`, `cancel-run` (git input artifact, Vault Agent init-only)
- [ ] `qops-tracker`: `FOR UPDATE SKIP LOCKED` polling, adaptive backoff, result fetch → Storage, outbox dispatcher, `/metrics`
- [ ] CLI: `qops run --cluster`, `qops status`, `qops logs`
- [ ] `experiments/ghz-emulator.yaml`

Definition of Done
- [ ] Committing `experiments/ghz-emulator.yaml` → run `SUCCEEDED`, CR status updated
- [ ] **Zero `qops-runs` pods during the emulated queue wait**
- [ ] A duplicate webhook is a no-op; killing the tracker mid-wait still completes the run
- [ ] `e2e.yml` runs this scenario on kind in CI

Cost: $0.

---

## P6 — Real QPU providers + cost guard
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

Cost: $0 (IBM Open Plan minutes, IonQ simulator).

---

## P7 — Iterative algorithms (VQE, QAOA)
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

## P8 — L3: error mitigation + GPU
**Goal:** pluggable mitigation with a real GPU path and a CPU fallback.

Build
- [ ] Stage plugin system (`prepare()` in L1, `apply()` in L3; entry points)
- [ ] `m3`, `zne` (Mitiq folding + extrapolation), `cdr` (Aer-GPU training-set simulation)
- [ ] `images/runtime-gpu` (CUDA, qiskit-aer-gpu, cupy), with a free-disk-space step in CI
- [ ] Device plugin time-slicing ×4; `accelerator: auto|gpu|cpu` scheduling

Definition of Done
- [ ] On the noisy emulator, ZNE+M3 reduces VQE energy error vs unmitigated
- [ ] The same run with `cpu` and with `gpu` gives matching results within tolerance
- [ ] GPU pods hold no QPU credentials (verified)

Cost: $0 (local GPU).

---

## P9 — L3: QEC experiments + decoders
**Goal:** error-correction experiments decoded on CPU and GPU.

Build
- [ ] `qec_repetition` (d = 3/5/7) and `qec_surface` (rotated d = 3, emulator)
- [ ] Stim circuit + detector error model from the same spec, with noise from backend calibration
- [ ] Decoders: `pymatching` (CPU), `cudaq-qec` (GPU), `ldpc` (CPU fallback)
- [ ] Batch decoding benchmark (shots/s CPU vs GPU)

Definition of Done
- [ ] Logical error rate decreases with distance on the emulator (below threshold)
- [ ] GPU and CPU decoders agree within statistical error; throughput benchmark published
- [ ] One repetition-code run on real IBM hardware

Cost: $0.

---

## P10 — Observability
**Goal:** see platform health, queue behavior, science results and cost in one place.

Build
- [ ] kube-prometheus-stack, Loki + Alloy via Argo CD
- [ ] Tracker metrics, Argo Workflows custom metrics, Grafana → Supabase (read-only role)
- [ ] Dashboards as code: Platform (zero-idle KPI), QPU, Science, Cost
- [ ] Alerts: quota ≥ 80%, READY-not-dispatched > 10 min, workflow failures, Vault sealed, Supabase unreachable

Definition of Done
- [ ] A full VQE run is visible end-to-end (convergence, queue waits, zero-idle KPI, quota)
- [ ] A forced test fires an alert

Cost: $0.

---

## P11 — Hardening & supply chain
**Goal:** production-grade guardrails.

Build
- [ ] Kyverno: PSS restricted, registry allowlist, required limits, cosign keyless `verifyImages`, **paid-provider gate**
- [ ] Default-deny NetworkPolicies (L3 egress only to Vault and Supabase)
- [ ] Argo CD AppProjects / RBAC
- [ ] CI: SBOM (syft) + cosign keyless signing + Trivy gate
- [ ] Vault raft snapshot CronJob; runbooks for Vault sealed / emulator down / Supabase paused

Definition of Done
- [ ] Unsigned images and paid experiments are both rejected at admission
- [ ] Every chaos scenario recovers by following its runbook

Cost: $0.

---

## P12 — Cloud phase (provider decided at phase start)
**Goal:** the same Git repo drives a second, cloud-hosted cluster.

Before starting, choose the target together. Options: Oracle Always Free (OKE Basic + Ampere A1 arm64, no GPU, so L3
falls back to CPU), stay local only, or a paid/trial option **only with explicit approval**.

Build
- [ ] `infra/<cloud>/` (OpenTofu) cluster + node pools mapped to the `qops.io/pool` labels
- [ ] `deploy/envs/<cloud>/` overlay; KMS auto-unseal for Vault
- [ ] Multi-arch images if needed (free `ubuntu-24.04-arm` runners)
- [ ] GPU node pool behind `enable_gpu_pool = false`

Definition of Done
- [ ] Both clusters sync from the same repo
- [ ] GHZ + VQE succeed in the cloud env

Cost: $0 unless you approve otherwise.

---

## Final acceptance
- [ ] Four committed experiments (GHZ on IBM, VQE on emulator with ZNE, QAOA on IonQ simulator, QEC repetition on emulator)
      all reach `SUCCEEDED` with no manual steps
- [ ] The zero-idle KPI shows no compute pods during QPU waits
- [ ] Paid spend = **$0**
