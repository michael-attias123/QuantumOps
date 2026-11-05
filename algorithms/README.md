# algorithms/ — L0 researcher code

Each algorithm lives in `algorithms/<name>/algorithm.py` as a plain Python class written with **pure Qiskit**.
It has no base class, no decorators, and **no `qops_*` imports**. CI enforces this rule (`tests/test_architecture.py`).

Next to it, `algorithm.yaml` declares the `kind` and default `config`; the platform calls `Algorithm(config)`.

| `kind` | Required methods | Optional |
|---|---|---|
| `sampling` | `circuits() -> list[QuantumCircuit]` | `analyze(distributions) -> dict` |
| `variational` | `ansatz()`, `hamiltonian() -> SparsePauliOp`, `initial_point()` | `exact_value()` |
| `qec-memory` | `code()` (P10) | — |

Full details: [ARCHITECTURE §6](../docs/ARCHITECTURE.md#6-l0--researcher-contract).

| Algorithm | Kind | What it does |
|---|---|---|
| [`ghz_benchmark`](ghz_benchmark/) | sampling | n-qubit GHZ state; fidelity estimate from Z and X measurements |
| [`vqe_h2`](vqe_h2/) | variational | VQE for H2 (2-qubit parity-reduced Hamiltonian at 0.735 Å) |

Run one locally: `uv run qops run --local algorithms/vqe_h2`. Create a new one: `uv run qops new algorithm <name> --kind variational`.
