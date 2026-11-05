"""The ``qops`` command-line interface.

Commands:

- ``qops run --local <path>``: run an algorithm in-process on the local Aer provider.
- ``qops run --resume <state.json>``: resume an interrupted local run.
- ``qops new algorithm <name> --kind sampling|variational``: scaffold a pure-Qiskit algorithm.

Cluster runs (``qops run --cluster``, ``status``, ``logs``) arrive in P6.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from qops_cli.scaffold import scaffold_algorithm

__version__ = "0.0.1"

__all__ = ["__version__", "build_parser", "main"]


def _parse_config(pairs: Sequence[str]) -> dict[str, Any]:
    config: dict[str, Any] = {}
    for pair in pairs:
        key, sep, raw = pair.partition("=")
        if not sep or not key:
            raise ValueError(f"--set expects key=value, got '{pair}'")
        try:
            config[key] = json.loads(raw)
        except json.JSONDecodeError:
            config[key] = raw
    return config


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="qops",
        description="QuantumOps: run hybrid quantum-classical experiments.",
    )
    parser.add_argument("--version", action="version", version=f"qops {__version__}")
    commands = parser.add_subparsers(dest="command")

    run = commands.add_parser("run", help="run an algorithm")
    target = run.add_mutually_exclusive_group(required=True)
    target.add_argument("--local", metavar="PATH", help="algorithm directory to run in-process")
    target.add_argument("--resume", metavar="STATE", help="resume from a state.json snapshot")
    run.add_argument("--provider", default="aer", help="provider name (default: aer)")
    run.add_argument(
        "--backend", default=None, help="backend (default: exact, or sampler with --shots)"
    )
    run.add_argument("--shots", type=int, default=None, help="shots per circuit (default: exact)")
    run.add_argument("--seed", type=int, default=7)
    run.add_argument("--maxiter", type=int, default=150, help="optimizer iterations (variational)")
    run.add_argument(
        "--max-steps", type=int, default=None, help="stop after N iterations (resumable)"
    )
    run.add_argument("--state-dir", type=Path, default=None, help="where to write state.json")
    run.add_argument(
        "--set", action="append", default=[], metavar="KEY=VALUE", help="config override"
    )
    run.add_argument("--json", action="store_true", help="print the full report as JSON")

    new = commands.add_parser("new", help="scaffold new resources")
    new_kinds = new.add_subparsers(dest="resource", required=True)
    algo = new_kinds.add_parser("algorithm", help="scaffold a pure-Qiskit algorithm")
    algo.add_argument("name")
    algo.add_argument("--kind", choices=["sampling", "variational"], required=True)
    algo.add_argument("--dir", type=Path, default=Path("algorithms"))
    return parser


def _cmd_run(args: argparse.Namespace) -> int:
    from qops_runtime import LocalRunOptions, run_local

    backend = args.backend or ("sampler" if args.shots else "exact")
    options = LocalRunOptions(
        provider=args.provider,
        backend=backend,
        shots=args.shots,
        seed=args.seed,
        maxiter=args.maxiter,
        config=_parse_config(args.set),
        state_dir=args.state_dir,
        max_steps=args.max_steps,
    )
    if args.state_dir is None and args.local:
        options.state_dir = Path(".qops") / "runs" / Path(args.local).name

    def progress(record: dict[str, Any]) -> None:
        if not args.json and record["iteration"] % 10 == 0:
            print(f"  iteration {record['iteration']:4d}  value {record['value']:.6f}")

    report = run_local(args.local, options, resume=args.resume, progress=progress)
    if args.json:
        print(json.dumps(report.to_dict(), indent=2, default=str))
        return 0
    print(f"{report.algorithm} ({report.kind.value}) run {report.run_id[:8]}")
    print(f"  finished: {report.finished}  iterations: {report.iterations}")
    shown = report.result.get("analysis", report.result)
    for key, value in shown.items():
        if key not in {"parameters", "distributions"}:
            print(f"  {key}: {value}")
    if report.state_path:
        print(f"  state: {report.state_path}")
    return 0


def _cmd_new(args: argparse.Namespace) -> int:
    created = scaffold_algorithm(args.dir, args.name, args.kind)
    print(f"created {created}")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "run":
            return _cmd_run(args)
        if args.command == "new":
            return _cmd_new(args)
    except (ValueError, FileExistsError, NotImplementedError) as exc:
        print(f"qops: error: {exc}", file=sys.stderr)
        return 2
    parser.print_help()
    return 0
