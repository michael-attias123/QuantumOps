# algorithms/ — L0 researcher code

Each algorithm lives in `algorithms/<name>/algorithm.py` as a plain Python class written with **pure Qiskit**.
It has no base class, no decorators, and **no `qops_*` imports**. CI enforces this rule (`tests/test_architecture.py`).

The class shape depends on the experiment `kind` (`sampling`, `variational`, `qec-memory`). See
[ARCHITECTURE §6](../docs/ARCHITECTURE.md#6-l0--researcher-contract). The first algorithms (`ghz_benchmark`, `vqe_h2`) arrive in P1.
