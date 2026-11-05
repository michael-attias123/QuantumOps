"""The ``qops`` command-line interface.

P0 only provides ``qops --version``; ``run``/``status``/``logs`` arrive in P1 and P6.
"""

from __future__ import annotations

import argparse
from collections.abc import Sequence

__version__ = "0.0.1"

__all__ = ["__version__", "build_parser", "main"]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="qops",
        description="QuantumOps: run hybrid quantum-classical experiments.",
    )
    parser.add_argument("--version", action="version", version=f"qops {__version__}")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    parser.parse_args(argv)
    parser.print_help()
    return 0
