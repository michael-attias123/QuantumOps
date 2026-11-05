# QuantumOps

[![ci](https://github.com/michael-attias123/QuantumOps/actions/workflows/ci.yml/badge.svg)](https://github.com/michael-attias123/QuantumOps/actions/workflows/ci.yml)

A GitOps-driven Kubernetes platform for **hybrid quantum-classical workloads** (VQE, QAOA, quantum error
correction). Researchers write plain Qiskit; the platform runs it across CPU, QPU and GPU without anything sitting
idle while jobs wait in cloud quantum queues.

| Level | Runs on | Does |
|---|---|---|
| **L0 · Code** | this repo (`algorithms/`) | pure Qiskit: no decorators, no infrastructure imports |
| **L1 · CPU** | Kubernetes CPU pool | build circuits, prepare mitigation/QEC, transpile, cost-check, submit, exit |
| **L2 · QPU** | quantum cloud API | IBM Quantum, IonQ simulator, Braket local simulator, in-cluster emulator |
| **L3 · GPU/CPU** | Kubernetes CPU pool + free remote GPU via API (Kaggle) | error mitigation (M3, ZNE, CDR), QEC decoding (PyMatching, CUDA-Q QEC), optimizer step |

**Stack:** k3s on Oracle Cloud Always Free (reached over Tailscale) · Kaggle GPU API · Argo CD · Argo Workflows · Argo Events · HashiCorp Vault · External Secrets ·
Supabase (Postgres + Storage) · Qiskit 2.x · Prometheus/Grafana/Loki · Kyverno · OpenTofu · GitHub Actions + GHCR

**Principles:** zero-idle compute · state hydration between ephemeral pods · event-driven and pull-based ·
GitOps for everything (including Vault config, DB schema and experiment runs) · **$0 budget with paid paths blocked by default**

## Documentation
- [Architecture](docs/ARCHITECTURE.md): full system design
- [Roadmap](docs/ROADMAP.md): phases P0–P12 with Definitions of Done
- [Original blueprint](docs/reference/original-blueprint.md): the starting idea

## Quickstart (any computer)
Requirements: `git` and [uv](https://docs.astral.sh/uv/).

```bash
git clone https://github.com/michael-attias123/QuantumOps.git && cd QuantumOps
make verify-p0
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for make targets and rules, and [docs/adr/](docs/adr/) for key decisions.

## Try it (no cluster needed)
```bash
uv run qops run --local algorithms/ghz_benchmark       # GHZ fidelity
uv run qops run --local algorithms/vqe_h2              # VQE for H2, converges to the exact energy
uv run qops run --local algorithms/vqe_h2 --max-steps 20   # stop early (writes state.json) ...
uv run qops run --resume .qops/runs/vqe_h2/state.json      # ... and resume with an identical trajectory
uv run qops new algorithm my_algo --kind variational        # scaffold a pure-Qiskit algorithm
```

## Status
**P0 — Foundations** and **P1 — L0 contract + local runtime** done. Next: **P2 — Cloud cluster (OCI Always Free + Tailscale)**.
