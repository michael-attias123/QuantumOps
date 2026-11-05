"""Provider registry backed by the ``qops.providers`` entry-point group.

Providers register in their package's ``pyproject.toml``::

    [project.entry-points."qops.providers"]
    aer = "qops_providers.aer:AerProvider"
"""

from __future__ import annotations

from importlib.metadata import entry_points

from qops_providers.base import ProviderError, QuantumProvider

GROUP = "qops.providers"


def available_providers() -> list[str]:
    return sorted(ep.name for ep in entry_points(group=GROUP))


def get_provider(name: str) -> QuantumProvider:
    matches = [ep for ep in entry_points(group=GROUP) if ep.name == name]
    if not matches:
        known = ", ".join(available_providers()) or "none"
        raise ProviderError(f"unknown provider '{name}' (available: {known})")
    provider = matches[0].load()()
    if not isinstance(provider, QuantumProvider):
        raise ProviderError(f"provider '{name}' does not implement the QuantumProvider interface")
    return provider
