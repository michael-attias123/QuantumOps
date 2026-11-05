import json
from pathlib import Path

import pytest

from qops_core.models import CircuitResult, ExperimentKind
from qops_core.state import SCHEMA_VERSION, RunState, StateError, load_state, save_state


def make_state() -> RunState:
    return RunState(
        kind=ExperimentKind.VARIATIONAL,
        algorithm="algorithms/vqe_h2",
        config={"reps": 2},
        provider="aer",
        backend="exact",
        shots=None,
        seed=7,
        optimizer={"name": "spsa", "x": [0.1, 0.2]},
        history=[{"iteration": 1, "value": -1.0}],
    )


def test_roundtrip(tmp_path: Path) -> None:
    state = make_state()
    path = save_state(state, tmp_path / "run" / "state.json")
    assert load_state(path) == state
    assert json.loads(path.read_text())["schema_version"] == SCHEMA_VERSION
    assert not path.with_suffix(".json.tmp").exists()


def test_rejects_other_schema_version() -> None:
    data = json.loads(make_state().to_json())
    data["schema_version"] = SCHEMA_VERSION + 1
    with pytest.raises(StateError, match="schema_version"):
        RunState.from_json(json.dumps(data))


def test_rejects_garbage_and_unknown_fields() -> None:
    with pytest.raises(StateError, match="not valid JSON"):
        RunState.from_json("{")
    data = json.loads(make_state().to_json())
    data["surprise"] = 1
    with pytest.raises(StateError, match="unexpected fields"):
        RunState.from_json(json.dumps(data))


def test_rejects_non_finite_values() -> None:
    state = make_state()
    state.history.append({"value": float("nan")})
    with pytest.raises(ValueError, match="Out of range float"):
        state.to_json()


def test_counts_to_probabilities() -> None:
    result = CircuitResult.from_counts({"00": 3, "11": 1})
    assert result.probabilities == {"00": 0.75, "11": 0.25}
    assert result.shots == 4
    with pytest.raises(ValueError, match="at least one shot"):
        CircuitResult.from_counts({})
