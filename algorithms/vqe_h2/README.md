# vqe_h2: Variational Quantum Eigensolver for H2

**Kind:** `variational` · **Config:** `reps` (ansatz layers, default 2) · **Role in the project:** the reference
iterative workload, exercising the CPU → QPU → post-processing loop many times per run

## The problem
Find the **ground-state energy** of the hydrogen molecule (H2) at its equilibrium bond length, 0.735 Å. This number
governs how the molecule binds and reacts. Classical computers solve H2 easily; it's the "hello world" of quantum
chemistry because the exact answer is known, so we can measure how close the quantum method gets.

## From molecule to qubits
1. **Basis set STO-3G:** each hydrogen atom gets one orbital, giving 2 spatial orbitals and 4 spin-orbitals.
2. **Fermion-to-qubit mapping:** the parity mapping plus two-qubit reduction uses symmetries (particle number and spin)
   to remove 2 qubits. **4 spin-orbitals become 2 qubits.**
3. The result is a 2-qubit Hamiltonian, a weighted sum of Pauli operators (energies in Hartree, Ha):

| Term | Coefficient (Ha) |
|---|---|
| `II` | −1.052373 |
| `IZ` | +0.397937 |
| `ZI` | −0.397937 |
| `ZZ` | −0.011280 |
| `XX` | +0.180931 |

The coefficients are hard-coded in `algorithm.py`; qiskit-nature, which used to compute them, is no longer maintained.

| Quantity | Value |
|---|---|
| Exact electronic ground-state energy (lowest eigenvalue) | **−1.857275 Ha** |
| + nuclear repulsion (0.719969 Ha) = total energy | −1.137306 Ha |
| Target precision ("chemical accuracy", ≈ 1 kcal/mol) | 1.6 mHa = 0.0016 Ha |

The run reports the electronic energy, which is what the Hamiltonian above describes.

## How VQE works
The **variational principle**: for any trial state |ψ(θ)⟩, the energy `E(θ) = ⟨ψ(θ)|H|ψ(θ)⟩` is **never lower** than the
true ground-state energy. So we can search over θ for the lowest E(θ):

```
        ┌──────────── classical optimizer (SPSA) ────────────┐
        │                                                    │
   θ ──►│ L1: bind θ into the ansatz, add measurement bases  │
        │ L2: run circuits on QPU / simulator                │
        │ L3: energy from outcomes → optimizer update → new θ│◄── repeat
        └────────────────────────────────────────────────────┘
```

The quantum computer does what it's good at: preparing and measuring a quantum state. A classical optimizer steers it.

### The ansatz (trial state)
`real_amplitudes(2, reps=2)`: layers of RY rotations with a CNOT between them, **6 parameters**:

```
q_0: ─RY(θ0)──■──RY(θ2)──■──RY(θ4)─
            ┌─┴─┐      ┌─┴─┐
q_1: ─RY(θ1)┤ X ├RY(θ3)┤ X ├RY(θ5)─
            └───┘      └───┘
```

The H2 Hamiltonian is real, so its ground state has real amplitudes; RY + CNOT is enough and needs fewer parameters
than a general ansatz, which means faster convergence. `reps=1` (4 parameters) also exists but converges only for
some seeds, so `reps=2` is the default. The starting point is θ = 0.1 for every parameter.

### Measuring the energy
A quantum computer only measures in the Z basis, so the platform **groups** Pauli terms that can be measured together
and adds basis rotations:

| Group | Terms | Circuit change |
|---|---|---|
| Z basis | `IZ`, `ZI`, `ZZ` | none |
| X basis | `XX` (+ the constant `II`) | H on both qubits |

So **one energy evaluation = 2 circuits**. Each term's value is computed from the measured probabilities (a parity
of the relevant bits), weighted by its coefficient, then summed. This happens in L3 from raw outcomes (ADR 0005),
which is what later lets our own error mitigation (P9) correct them.

### The optimizer: SPSA
SPSA (Simultaneous Perturbation Stochastic Approximation) estimates the gradient from just **two** energy
evaluations per step, at `θ + cΔ` and `θ − cΔ` with a random ±1 direction Δ, regardless of the number of parameters.
It also tolerates noisy energies well, which is why it's a standard choice for real quantum hardware.

| Per iteration | Count |
|---|---|
| energy evaluations | 2 |
| circuits | 4 (2 points × 2 measurement groups) |
| QPU jobs | **1** (all 4 circuits batched) |

The optimizer's complete state, its random generator included, is saved after every iteration. A run stopped at
iteration 13 and resumed elsewhere gives **exactly** the same result as one that never stopped. That's what lets each
iteration run in a different pod in later phases.

## Output
| Field | Meaning |
|---|---|
| `energy` | ⟨H⟩ at the final parameters (one last evaluation) |
| `exact` | the exact answer, −1.857275 Ha |
| `error` | `energy − exact`; below 0.0016 Ha means chemical accuracy |
| `best_estimate` | lowest average of the two perturbed evaluations seen during the run |
| `parameters` | final θ (6 values) |

## What to expect
| Setting | Typical error |
|---|---|
| exact, 150 iterations (default) | ~1e-6 Ha ✅ far below chemical accuracy, < 1 s |
| `--shots 4000`, 100 iterations | 1e-4 to 4e-3 Ha depending on the seed: shot noise of a few mHa, so chemical accuracy is **not** guaranteed; use more shots. The estimate can even dip slightly *below* exact, because the variational bound holds only for the exact expectation |
| 20–40 iterations | ❌ 0.27–0.64 Ha: SPSA hasn't converged yet |
| Real IBM hardware (P8) | limited by noise until error mitigation (P9) |

**Known limitation:** IBM's free plan gives 10 QPU-minutes a month, so before using real hardware P8 must make
convergence work with far fewer iterations (better step-size calibration, a smaller ansatz, or a different resumable
optimizer).

## Try it
```bash
uv run qops run --local algorithms/vqe_h2
uv run qops run --local algorithms/vqe_h2 --shots 4000 --maxiter 100
uv run qops run --local algorithms/vqe_h2 --seed 42
uv run qops run --local algorithms/vqe_h2 --max-steps 20 && uv run qops run --resume .qops/runs/vqe_h2/state.json
```
