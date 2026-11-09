# QuantumOps — Delivery Roadmap

Build one phase at a time. A phase is **done** only when CI is green and every item in its *Definition of Done* is
checked, with each check scripted as `make verify-pN`. The design behind each item is in [ARCHITECTURE.md](ARCHITECTURE.md).

**Ground rules for every phase**
- **$0.** If a step would cost money, stop and ask first. Paid paths stay disabled by default.
- **GitOps.** If it runs in the cluster, it's declared in Git. The only imperative steps are `tofu apply` for the
  cluster and the Vault init/seed scripts.
- **No secrets in Git.** Secrets go through `make seed-secrets` → Vault, or as sensitive OpenTofu variables. gitleaks runs in CI.
- **One branch per phase:** `phase/pN-<slug>` from `main` → PR → merge commit → tag `pN-<slug>` → delete the branch
  ([ADR 0009](adr/0009-repository-layout-and-branches.md)). New folders appear only when the phase fills them.
- **Work from any computer.** Each machine needs only `git`, `uv`, `tailscale`, `kubectl` (plus `tofu` for P2). Nothing
  depends on one particular laptop.
- Each phase ends with updated docs (ADRs, runbooks) for whatever it introduced, **and a phase overview in
  [`docs/phases/pN-overview.md`](phases/)**: goal, what was built, how to use it, DoD evidence, decisions, limitations, next steps.

| # | Phase | Levels touched | Depends on | Status |
|---|---|---|---|---|
| P0 | [Foundations](phases/p0-overview.md) | — | — | ✅ |
| P1 | [L0 contract + local runtime](phases/p1-overview.md) | L0, L1, L3 (in-process) | P0 | ✅ |
| P2 | [Cloud cluster (OCI Always Free + Tailscale)](phases/p2-overview.md) | platform | P0 | ✅ |
| T | [OCI trial GPU spike](adr/0010-oci-trial-burst-layer.md) (optional, ends on trial day 27) | L3 | P2 | dropped |
| P3 | [GitOps bootstrap](phases/p3-overview.md) | platform | P2 | ✅ |
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
- [x] Monorepo skeleton matching [ARCHITECTURE §13](ARCHITECTURE.md#13-gitops-repository-layout-cicd)
- [x] uv workspace (`packages/*`), Python 3.12, ruff, mypy, pytest, pre-commit
- [x] `Makefile` with targets `lint`, `test`, `verify-p0`
- [x] `docs/adr/` with the first ADRs: monorepo, OCI + Tailscale, Supabase, Git-manifest trigger, Sampler-everywhere,
      remote GPU via Kaggle, $0 policy
- [x] Renovate config; `ci.yml` (lint + test + gitleaks) on amd64 **and** arm64 runners
- [x] `infra/ci/kind-config.yaml` for later e2e tests

Definition of Done
- [x] Fresh clone on any computer: `uv sync && make lint test` passes
- [x] CI green on a PR (both architectures)

Cost: $0.

---

## P1 — L0 contract + local runtime (no Kubernetes)
**Goal:** researchers can write pure Qiskit and run the full loop in-process on any laptop.

Build
- [x] `qops-core`: contract loader (`sampling`, `variational`, `qec-memory`), models, state serde (`state.json` + `schema_version`), QPY helpers
- [x] `qops-providers`: provider interface + capability flags, synchronous `aer` provider
- [x] `qops-stages`: SPSA ask/tell with JSON state; measurement grouping + expectation values from counts
- [x] `qops-cli`: `qops run --local <path>`, `qops new algorithm <name> --kind …`
- [x] Algorithms: `ghz_benchmark`, `vqe_h2`
- [x] Version pin matrix for Qiskit 2.x + qiskit-aer + mthree + mitiq + qiskit-ionq + qiskit-braket-provider, tested on amd64 **and arm64**

Definition of Done
- [x] GHZ run reports fidelity
- [x] VQE-H2 (noiseless) reaches the exact energy within 1.6 mHa
- [x] Interrupting and resuming from saved state reproduces an identical trajectory (seeded)
- [x] Algorithms contain zero platform imports (checked by a lint rule)

Notes from delivery
- Results are provider-neutral **probabilities** (`CircuitResult`); exact simulators return exact distributions, real
  backends return counts that are normalized. Contract signatures: `circuits()`, `analyze(distributions)`.
- SPSA with automatic calibration converges for VQE-H2 in ~100–150 iterations (error ≈ 1e-6 Ha noiseless), but is
  still far off at 20–40 iterations. **P8 must tune for small iteration budgets** before spending IBM QPU time
  (better calibration, fewer parameters, or a resumable gradient-free optimizer).
- Pin matrix: [compat-matrix.md](reference/compat-matrix.md).

Cost: $0.

---

## P2 — Cloud cluster (OCI Always Free + Tailscale)
**Goal:** an always-on, private, $0 cluster reachable from every computer.

Prerequisites (one-time, by you, ~15 min): see **[Before P2](phases/p2-prerequisites.md)**. Sign-ups, browser
logins, a Tailscale API token and the HTTPS toggle are manual; tools, OCI API key, limits, budgets, state bucket and S3
key are scripted (`make tools-admin oci-login oci-bootstrap tailscale-login prereqs-report`, in `infra/bootstrap/`).

Build
- [x] `infra/oci/` (OpenTofu): VCN + subnet, security lists with **no public inbound**, **1× `VM.Standard.A1.Flex` (2 OCPU / 12 GB)**: the whole Always Free A1 allowance ([ADR 0008](adr/0008-single-node-a1-cluster.md))
- [x] Tailscale provider in the same stack: tailnet policy (tags) + MagicDNS from Git, and a 1-hour tagged auth key minted at `apply` (no hand-made keys)
- [x] cloud-init: Tailscale join with that key, single-node k3s bound to the tailnet IP, node label `qops.io/pool=cpu`, Traefik/servicelb disabled (Tailscale operator exposes services)
- [x] OCI KMS key (free) for later Vault auto-unseal
- [x] Remote state in OCI Object Storage (S3 backend) + OpenTofu state encryption
- [x] `make kubeconfig` (fetch kubeconfig over Tailscale), `make ssh-server`
- [x] Runbook: A1 capacity errors, idle-reclaim policy, rebuilding the cluster from scratch ([oci-cluster](runbooks/oci-cluster.md)); [ADR 0011](adr/0011-tailnet-and-node-key-in-opentofu.md)
- [x] `make infra-check` (fmt, validate, 8 tests with mocked providers) in CI; `make verify-p2`

Definition of Done
- [x] `make kubeconfig && kubectl get nodes` → 1 Ready arm64 node (admin computer; any tailnet computer works the same way)
- [x] The VMs' public IPs answer on no port (checked from outside the tailnet)
- [x] `tofu plan` shows no drift (`make verify-p2`); the OCI cost report shows $0 (follow-up check, budget alert armed)

Risks: A1 capacity (retry or try another availability domain), idle reclaim (a running cluster stays busy). · Cost: $0.

Trial guardrails ([ADR 0010](adr/0010-oci-trial-burst-layer.md))
- [x] `infra/oci/` validation: A1 `ocpus <= 2 && memory_gb <= 12`
- ~~`infra/oci-trial/`, `make/trial.mk`, teardown runbook~~ — not built: trial tenancies can't request a GPU limit
  (Oracle: "not eligible to submit a limit request"), so track T is dropped. The optional 2-node rehearsal isn't
  worth a separate stack; the trial adds nothing else to P2.

---

## T — OCI trial GPU spike (optional, time-boxed)
**Goal:** measure the GPU paths of L3 on credits, before P9/P10 depend on them. Runs only while the trial lasts.

Build
- [ ] `research/experiments/gpu-spike/`: qiskit-aer-gpu vs CPU Aer on `ghz_benchmark` and `vqe_h2` at growing widths; cudaq-qec vs PyMatching, surface-code memory d = 3–9
- [ ] Build and run the planned Kaggle GPU image on the A10
- [ ] `docs/reference/gpu-spike.md`: numbers + go/no-go per GPU path

Definition of Done
- [ ] Results committed; `make trial-down && make trial-audit` → 0 trial resources, A1 ≤ 2 OCPU / 12 GB

Prerequisite: GPU A10 limit ≥ 1. If Oracle refuses it, this track is dropped. · Cost: ≤ $150 of trial credits, $0 cash.

**Status (2026-11-09): dropped.** The GPU A10 limit is 0 and trial tenancies can't request an increase. GPU work stays
on Kaggle in P9 as planned.

---

## P3 — GitOps bootstrap
**Goal:** one command installs the whole platform from Git.

Build
- [x] `deploy/bootstrap/` (Argo CD Helm values + root Application) and `deploy/apps/` app-of-apps chart
- [x] Sync waves and namespaces; Argo CD manages its own release
- [x] Tailscale Kubernetes operator; Argo CD UI at `argocd.<tailnet>.ts.net`
- [x] `deploy/envs/oci/` and `deploy/envs/ci/`
- [x] `images.yml`: multi-arch build (native arm64 + amd64 runners) → GHCR → bot commits tags into `deploy/envs/oci`
- [x] `infra/github/` (OpenTofu): branch protection, required checks
- [x] `make bootstrap`
- [x] [ADR 0012](adr/0012-gitops-bootstrap.md), [runbook](runbooks/gitops.md); `make deploy-check` (helm lint + kubeconform) in CI; `make verify-p3`

Definition of Done
- [x] On a freshly rebuilt cluster, `make bootstrap` → all apps Synced/Healthy with no manual kubectl
- [x] A Git change to a value shows up in the cluster
- [x] An image built on `main` gets its tag bumped and deployed automatically
- [x] The Argo CD UI opens from any tailnet computer and from nowhere else

Cost: $0.

---

## P4 — Vault + External Secrets
**Goal:** every credential comes from Vault; Vault config is GitOps; no laptop needed after a restart.

Build
- [ ] Vault (Raft standalone, injector, audit device) with **OCI KMS auto-unseal**
- [ ] `deploy/bootstrap/scripts/vault-init.sh`, `make seed-secrets`; recovery keys stored outside the repo; `make unseal` fallback
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
- [ ] `packages/qops-core/migrations/` (dbmate): `runs`, `iterations`, `remote_jobs`, `outbox`, `qpu_usage`, `gpu_usage`, `backend_cache`; RLS on, no policies
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
- [ ] `research/experiments/ghz-emulator.yaml`; `e2e.yml` on kind

Definition of Done
- [ ] Committing `research/experiments/ghz-emulator.yaml` → run `SUCCEEDED`, CR status updated
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
- [ ] `packages/qops-providers/src/qops_providers/gpu/kaggle/` kernel template: installs `qops-stages` at the pinned SHA, reads input and writes output only through signed URLs
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
- [ ] kube-prometheus-stack (short retention), Loki (filesystem) + Alloy via Argo CD, sized for the 12 GB node (single replicas, ≤ 2 GB for the whole monitoring stack)
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
