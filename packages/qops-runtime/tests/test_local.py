"""P1 Definition of Done, exercised end to end through the in-process runtime."""

import json
from pathlib import Path

import pytest

from qops_core.state import load_state
from qops_runtime import LocalRunOptions, run_local

REPO = Path(__file__).resolve().parents[3]
GHZ = REPO / "algorithms" / "ghz_benchmark"
VQE = REPO / "algorithms" / "vqe_h2"
CHEMICAL_ACCURACY = 1.6e-3  # Ha


@pytest.mark.parametrize("num_qubits", [2, 3, 5])
def test_ghz_reports_fidelity(num_qubits: int) -> None:
    report = run_local(GHZ, LocalRunOptions(config={"num_qubits": num_qubits}))
    assert report.finished
    assert report.result["analysis"]["fidelity"] == pytest.approx(1.0, abs=1e-9)


def test_ghz_with_shots() -> None:
    report = run_local(GHZ, LocalRunOptions(backend="sampler", shots=2000, seed=3))
    assert report.result["analysis"]["fidelity"] == pytest.approx(1.0, abs=0.05)


def test_vqe_h2_reaches_chemical_accuracy(tmp_path: Path) -> None:
    report = run_local(VQE, LocalRunOptions(maxiter=150, state_dir=tmp_path))
    assert report.finished
    assert report.iterations == 150
    assert abs(report.result["error"]) < CHEMICAL_ACCURACY
    state = load_state(tmp_path / "state.json")
    assert state.finished
    assert len(state.history) == 150


def test_resume_reproduces_identical_trajectory(tmp_path: Path) -> None:
    full = run_local(VQE, LocalRunOptions(maxiter=40, state_dir=tmp_path / "full"))
    partial = run_local(VQE, LocalRunOptions(maxiter=40, state_dir=tmp_path / "part", max_steps=13))
    assert not partial.finished
    assert partial.iterations == 13
    assert partial.state_path is not None
    resumed = run_local(resume=partial.state_path)
    assert resumed.finished
    assert resumed.iterations == 40
    full_state = json.loads((tmp_path / "full" / "state.json").read_text())
    resumed_state = json.loads((tmp_path / "part" / "state.json").read_text())
    assert resumed_state["history"] == full_state["history"]
    assert resumed.result["energy"] == full.result["energy"]


def test_qec_kind_not_yet_supported(tmp_path: Path) -> None:
    algo = tmp_path / "qec"
    algo.mkdir()
    (algo / "algorithm.yaml").write_text("kind: qec-memory\n")
    (algo / "algorithm.py").write_text(
        "class Algorithm:\n    def __init__(self, c):\n        pass\n    def code(self):\n        return {}\n"
    )
    with pytest.raises(NotImplementedError, match="P10"):
        run_local(algo)
