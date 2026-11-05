# research/algorithms/ — researcher code (L0)

This folder is where the **science** lives. Everything here is plain Python + Qiskit. An algorithm never knows whether it
runs on your laptop, on the cluster, on a simulator or on real IBM hardware: the platform decides that.

| Algorithm | Kind | In one sentence | Details |
|---|---|---|---|
| [`ghz_benchmark`](ghz_benchmark/) | `sampling` | Entangle n qubits into a GHZ state and measure how well the backend did it | [README](ghz_benchmark/README.md) |
| [`vqe_h2`](vqe_h2/) | `variational` | Find the ground-state energy of the H2 molecule with the Variational Quantum Eigensolver | [README](vqe_h2/README.md) |

Coming later: `qaoa_maxcut` (P8, variational), `qec_repetition` and `qec_surface` (P10, qec-memory).

---

## How an algorithm moves through the platform

```
 L0  algorithms/<name>/          your pure-Qiskit class
       │
 L1  CPU                         platform builds/binds circuits, adds measurement bases, transpiles, submits
       │
 L2  QPU / simulator             circuits run; results come back as outcome probabilities
       │
 L3  CPU (or remote GPU, P9)     platform computes energies / mitigation / decoding, steps the optimizer
       │
       └── variational: back to L1 for the next iteration · sampling: finish and report
```

Today (P1) all of these steps run in one process (`qops run --local`). From P6 each step is a separate short-lived
pod on the cluster, and no pod exists while a job waits in a QPU queue. **Your algorithm code doesn't change.**

## The three kinds

The `kind` in `algorithm.yaml` tells the platform which loop to run, and therefore which methods your class needs.

### `sampling`: run circuits once, analyze the outcomes
```python
class Algorithm:
    def __init__(self, config: dict): ...
    def circuits(self) -> list[QuantumCircuit]: ...            # required, with measurements
    def analyze(self, distributions: list[dict[str, float]]) -> dict: ...   # optional
```
`distributions[i]` holds the outcome probabilities of `circuits()[i]`, e.g. `{"000": 0.5, "111": 0.5}`. Bitstrings use
Qiskit order: the **rightmost** character is classical bit 0. Use it for benchmarks, state characterization, and
one-shot experiments.

### `variational`: optimize circuit parameters to minimize an energy
```python
class Algorithm:
    def __init__(self, config: dict): ...
    def ansatz(self) -> QuantumCircuit: ...       # required, parameterized, no measurements
    def hamiltonian(self) -> SparsePauliOp: ...   # required, the observable to minimize
    def initial_point(self) -> list[float]: ...   # required, one value per ansatz parameter
    def exact_value(self) -> float: ...           # optional, enables the "error" in the report
```
You describe the **physics**: the trial state and the Hamiltonian. The platform owns everything else: the optimizer
(SPSA), splitting the Hamiltonian into measurable groups, adding basis rotations, computing ⟨H⟩ from outcomes, and
saving state every iteration so a run can stop and resume. Used for VQE and QAOA.

### `qec-memory`: quantum error-correction experiments (from P10)
```python
class Algorithm:
    def code(self) -> dict: ...   # e.g. {"family": "repetition", "distance": 5, "rounds": 3, "basis": "Z"}
```
The platform will build the syndrome-extraction circuits, run them, and decode them on CPU or remote GPU.

## Rules (CI enforces them)
1. **No platform imports.** Nothing here may import `qops_*`. `tests/test_architecture.py` fails the build otherwise.
2. **Config comes in through `__init__`.** Defaults live in `algorithm.yaml`; runs can override them
   (`--set key=value`, or `spec.algorithm.config` in an experiment).
3. **Deterministic and side-effect free.** No file or network access, no global random state: the same config must
   give the same circuits, because runs are resumed in other processes.
4. Every folder must load cleanly for its kind (`tests/test_algorithms.py`).

## Run, resume, create
```bash
uv run qops run --local research/algorithms/ghz_benchmark                  # exact (noiseless) probabilities
uv run qops run --local research/algorithms/ghz_benchmark --shots 2000     # shot-based sampling
uv run qops run --local research/algorithms/ghz_benchmark --set num_qubits=6
uv run qops run --local research/algorithms/vqe_h2 --maxiter 150 --seed 7
uv run qops run --local research/algorithms/vqe_h2 --max-steps 20          # stop early, state in .qops/runs/vqe_h2/
uv run qops run --resume .qops/runs/vqe_h2/state.json             # continue, identical trajectory
uv run qops run --local research/algorithms/vqe_h2 --json                  # machine-readable report
uv run qops new algorithm my_algo --kind variational              # scaffold a new, valid algorithm
```

| Flag | Meaning |
|---|---|
| `--shots N` | sample N shots per circuit (default: exact probabilities, noiseless) |
| `--maxiter N` | optimizer iterations (variational) |
| `--seed N` | makes optimizer and sampling reproducible |
| `--max-steps N` | stop after N iterations in this process (resumable) |
| `--set k=v` | override a config value (`v` is parsed as JSON when possible) |
| `--state-dir DIR` | where `state.json` is written |

## Writing your own: checklist
1. `uv run qops new algorithm my_algo --kind variational` (or `sampling`).
2. Edit `algorithm.py` with Qiskit only, and put tunable values in `algorithm.yaml` under `config`.
3. `uv run qops run --local research/algorithms/my_algo`.
4. `make test` (the contract and purity checks run automatically).
5. Commit. From P6, adding a `research/experiments/<name>.yaml` that points at it runs it on the cluster.
