"""Architecture guards: enforce layering rules from docs/ARCHITECTURE.md by scanning imports.

- Researcher code under ``research/algorithms/`` must stay pure Qiskit: no ``qops_*`` imports.
- ``qops_core`` is the bottom layer: it must not import any other ``qops_*`` package.
"""

from __future__ import annotations

import ast
from collections.abc import Iterator
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]


def imported_modules(path: Path) -> Iterator[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                yield alias.name
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            yield node.module


def violations(root: Path, forbidden: tuple[str, ...]) -> list[str]:
    found = []
    for path in sorted(root.rglob("*.py")):
        for module in imported_modules(path):
            top = module.split(".")[0]
            if top in forbidden or any(top.startswith(prefix) for prefix in forbidden):
                found.append(f"{path.relative_to(REPO_ROOT)} imports {module}")
    return found


def test_imported_modules_parses_both_import_forms(tmp_path: Path) -> None:
    sample = tmp_path / "sample.py"
    sample.write_text("import qops_core\nfrom qops_stages.zne import x\nfrom . import y\n")
    assert list(imported_modules(sample)) == ["qops_core", "qops_stages.zne"]


def test_algorithms_are_pure_qiskit() -> None:
    algorithms = REPO_ROOT / "research" / "algorithms"
    if not algorithms.exists():
        pytest.skip("no research/algorithms/ directory")
    assert violations(algorithms, ("qops_",)) == []


def test_core_is_bottom_layer() -> None:
    core = REPO_ROOT / "packages" / "qops-core" / "src" / "qops_core"
    others = tuple(
        p.name.replace("-", "_")
        for p in (REPO_ROOT / "packages").iterdir()
        if p.is_dir() and p.name != "qops-core"
    )
    assert violations(core, others) == []
