from pathlib import Path

import pytest

from qops_core.contract import ContractError, load_algorithm, load_metadata
from qops_core.models import ExperimentKind


def write(directory: Path, yaml_text: str, code: str) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "algorithm.yaml").write_text(yaml_text)
    (directory / "algorithm.py").write_text(code)
    return directory


SAMPLING = """
class Algorithm:
    def __init__(self, config):
        self.config = config
    def circuits(self):
        return []
"""


def test_loads_and_merges_config(tmp_path: Path) -> None:
    path = write(tmp_path / "a", "kind: sampling\nconfig:\n  n: 2\n  m: 1\n", SAMPLING)
    loaded = load_algorithm(path, {"m": 5})
    assert loaded.kind is ExperimentKind.SAMPLING
    assert loaded.config == {"n": 2, "m": 5}
    assert loaded.instance.config == {"n": 2, "m": 5}
    assert loaded.metadata.name == "a"
    assert loaded.has("circuits")
    assert not loaded.has("analyze")


def test_missing_required_method(tmp_path: Path) -> None:
    path = write(tmp_path / "v", "kind: variational\n", SAMPLING)
    with pytest.raises(ContractError, match="ansatz, hamiltonian, initial_point"):
        load_algorithm(path)


def test_invalid_kind(tmp_path: Path) -> None:
    path = write(tmp_path / "k", "kind: banana\n", SAMPLING)
    with pytest.raises(ContractError, match="kind must be one of"):
        load_metadata(path)


def test_missing_files_and_class(tmp_path: Path) -> None:
    with pytest.raises(ContractError, match=r"missing algorithm\.yaml"):
        load_algorithm(tmp_path)
    path = write(tmp_path / "c", "kind: sampling\n", "x = 1\n")
    with pytest.raises(ContractError, match="class named Algorithm"):
        load_algorithm(path)
