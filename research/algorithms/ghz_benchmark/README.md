# ghz_benchmark: GHZ state fidelity

**Kind:** `sampling` · **Config:** `num_qubits` (default 3) · **Role in the project:** end-to-end smoke test and
hardware benchmark

## What a GHZ state is
The Greenberger–Horne–Zeilinger state of n qubits is

```
|GHZ⟩ = ( |00…0⟩ + |11…1⟩ ) / √2
```

All qubits are maximally correlated: measure one, and you know all the others. It's also fragile, because a single
error on any qubit destroys the coherence between the two branches. That makes it a good, cheap **benchmark**. Its
quality drops quickly as n grows on real hardware, so the number says a lot about a backend's gates and readout.

## The circuit
A Hadamard puts qubit 0 in superposition, then a chain of CNOTs copies it onto every other qubit:

```
        ┌───┐
   q_0: ┤ H ├──■─────────── M
        └───┘┌─┴─┐
   q_1: ─────┤ X ├──■────── M
             └───┘┌─┴─┐
   q_2: ──────────┤ X ├──── M
                  └───┘
```

The algorithm returns **two** circuits:

| Circuit | Extra gates | What it measures |
|---|---|---|
| `ghz_z` | none | **population** `P = P(00…0) + P(11…1)`: are we in the right two states? |
| `ghz_x` | H on every qubit | **parity** `⟨X⊗X⊗…⊗X⟩`: is the superposition coherent, rather than just a 50/50 mixture? |

The second measurement matters. A classical coin flip that gives all-0 or all-1 has population 1 but parity 0, while
a real GHZ state has parity +1. In the X basis, a GHZ state only produces bitstrings with an **even** number of 1s, so
`parity_x = Σ p(b)·(−1)^{#1s in b}`.

## Output
| Field | Ideal value | Meaning |
|---|---|---|
| `num_qubits` | n | size of the state |
| `population` | 1.0 | probability of landing in 00…0 or 11…1 |
| `parity_x` | 1.0 | coherence between the two branches |
| `fidelity` | 1.0 | estimate `(population + parity_x) / 2` |

**About the fidelity estimate.** The fidelity with the ideal state is `F = (ρ₀₀ + ρ₁₁)/2 + Re ρ₀₁`, where ρ₀₁ is the
coherence between |00…0⟩ and |11…1⟩. The population term is measured exactly. `⟨X⊗n⟩` equals `2·Re ρ₀₁` *plus*
coherences between other complementary pairs of bitstrings. Those are ≈ 0 under common noise (dephasing,
depolarizing), so the estimate is accurate in practice but **not** a strict bound. An exact measurement needs parity
oscillations, measuring at n+1 phase angles. That can be added later without changing the platform.

## What to expect
| Where | Result |
|---|---|
| `qops run --local` (exact) | 1.0 for any n |
| `--shots 2000` | ≈ 1.0 ± a few % (statistics only) |
| Real IBM hardware (P7) | lower, and falling with n; typically ~0.9 for 3 qubits, much lower beyond ~10 |

## Try it
```bash
uv run qops run --local research/algorithms/ghz_benchmark
uv run qops run --local research/algorithms/ghz_benchmark --set num_qubits=8 --shots 4000
```
