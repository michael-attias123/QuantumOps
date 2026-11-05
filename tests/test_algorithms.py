"""Every algorithm under research/algorithms/ satisfies the L0 contract for its declared kind."""

from pathlib import Path

import pytest

from qops_core.contract import load_algorithm

ALGORITHMS = sorted(
    p
    for p in (Path(__file__).resolve().parents[1] / "research" / "algorithms").iterdir()
    if p.is_dir()
)


@pytest.mark.parametrize("path", ALGORITHMS, ids=lambda p: p.name)
def test_algorithm_satisfies_contract(path: Path) -> None:
    loaded = load_algorithm(path)
    assert loaded.metadata.name == path.name
