"""L0 researcher contract: load a pure-Qiskit algorithm from ``algorithms/<name>/``.

An algorithm directory contains:

- ``algorithm.py`` defining a plain class ``Algorithm(config: dict)``. No base class, no
  decorators, no ``qops_*`` imports.
- ``algorithm.yaml`` with ``kind`` (sampling | variational | qec-memory) and default ``config``.

The methods the class must provide depend on ``kind`` (see ``REQUIRED_METHODS``).
"""

from __future__ import annotations

import importlib.util
import sys
from dataclasses import dataclass, field
from pathlib import Path
from types import ModuleType
from typing import Any

import yaml

from qops_core.models import ExperimentKind

REQUIRED_METHODS: dict[ExperimentKind, tuple[str, ...]] = {
    ExperimentKind.SAMPLING: ("circuits",),
    ExperimentKind.VARIATIONAL: ("ansatz", "hamiltonian", "initial_point"),
    ExperimentKind.QEC_MEMORY: ("code",),
}
OPTIONAL_METHODS: dict[ExperimentKind, tuple[str, ...]] = {
    ExperimentKind.SAMPLING: ("analyze",),
    ExperimentKind.VARIATIONAL: ("exact_value",),
    ExperimentKind.QEC_MEMORY: (),
}

ALGORITHM_FILE = "algorithm.py"
METADATA_FILE = "algorithm.yaml"
CLASS_NAME = "Algorithm"


class ContractError(ValueError):
    """The algorithm directory does not satisfy the L0 contract."""


@dataclass(frozen=True)
class AlgorithmMetadata:
    name: str
    kind: ExperimentKind
    config: dict[str, Any] = field(default_factory=dict)
    description: str = ""


@dataclass(frozen=True)
class LoadedAlgorithm:
    metadata: AlgorithmMetadata
    config: dict[str, Any]
    instance: Any
    path: Path

    @property
    def kind(self) -> ExperimentKind:
        return self.metadata.kind

    def has(self, method: str) -> bool:
        return callable(getattr(self.instance, method, None))

    def call(self, method: str, *args: Any) -> Any:
        return getattr(self.instance, method)(*args)


def load_metadata(path: Path) -> AlgorithmMetadata:
    meta_file = path / METADATA_FILE
    if not meta_file.is_file():
        raise ContractError(f"{path}: missing {METADATA_FILE}")
    raw = yaml.safe_load(meta_file.read_text(encoding="utf-8")) or {}
    if not isinstance(raw, dict):
        raise ContractError(f"{meta_file}: expected a mapping")
    try:
        kind = ExperimentKind(str(raw.get("kind")))
    except ValueError as exc:
        allowed = ", ".join(k.value for k in ExperimentKind)
        raise ContractError(f"{meta_file}: kind must be one of: {allowed}") from exc
    config = raw.get("config") or {}
    if not isinstance(config, dict):
        raise ContractError(f"{meta_file}: config must be a mapping")
    return AlgorithmMetadata(
        name=str(raw.get("name", path.name)),
        kind=kind,
        config=config,
        description=str(raw.get("description", "")),
    )


def _import_module(path: Path) -> ModuleType:
    source = path / ALGORITHM_FILE
    if not source.is_file():
        raise ContractError(f"{path}: missing {ALGORITHM_FILE}")
    module_name = f"qops_algorithm_{path.resolve().name}_{abs(hash(source.resolve()))}"
    spec = importlib.util.spec_from_file_location(module_name, source)
    if spec is None or spec.loader is None:
        raise ContractError(f"{source}: cannot be imported")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(module_name, None)
        raise
    return module


def load_algorithm(path: str | Path, overrides: dict[str, Any] | None = None) -> LoadedAlgorithm:
    """Import ``algorithm.py``, instantiate ``Algorithm(config)`` and validate it for its kind."""
    directory = Path(path)
    metadata = load_metadata(directory)
    module = _import_module(directory)
    cls = getattr(module, CLASS_NAME, None)
    if not isinstance(cls, type):
        raise ContractError(f"{directory / ALGORITHM_FILE}: must define a class named {CLASS_NAME}")
    config = {**metadata.config, **(overrides or {})}
    instance = cls(config)
    missing = [
        m for m in REQUIRED_METHODS[metadata.kind] if not callable(getattr(instance, m, None))
    ]
    if missing:
        raise ContractError(
            f"{directory}: kind '{metadata.kind}' requires method(s): {', '.join(missing)}"
        )
    return LoadedAlgorithm(metadata=metadata, config=config, instance=instance, path=directory)
