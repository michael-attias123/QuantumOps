import json
from pathlib import Path

import pytest

import qops_cli
from qops_core.contract import load_algorithm

REPO = Path(__file__).resolve().parents[3]


def test_version() -> None:
    assert qops_cli.__version__ == "0.0.1"


def test_version_flag(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        qops_cli.main(["--version"])
    assert exc.value.code == 0
    assert capsys.readouterr().out.strip() == "qops 0.0.1"


def test_no_args_prints_help(capsys: pytest.CaptureFixture[str]) -> None:
    assert qops_cli.main([]) == 0
    assert "usage: qops" in capsys.readouterr().out


def test_run_local_json(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    code = qops_cli.main(
        [
            "run",
            "--local",
            str(REPO / "algorithms" / "ghz_benchmark"),
            "--set",
            "num_qubits=4",
            "--state-dir",
            str(tmp_path),
            "--json",
        ]
    )
    assert code == 0
    report = json.loads(capsys.readouterr().out)
    assert report["finished"] is True
    assert report["result"]["analysis"]["num_qubits"] == 4
    assert (tmp_path / "state.json").is_file()


def test_run_and_resume_variational(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    vqe = str(REPO / "algorithms" / "vqe_h2")
    args = [
        "run",
        "--local",
        vqe,
        "--maxiter",
        "20",
        "--max-steps",
        "5",
        "--state-dir",
        str(tmp_path),
    ]
    assert qops_cli.main(args) == 0
    assert "finished: False" in capsys.readouterr().out
    assert qops_cli.main(["run", "--resume", str(tmp_path / "state.json"), "--json"]) == 0
    report = json.loads(capsys.readouterr().out)
    assert report["finished"] is True
    assert report["iterations"] == 20


def test_run_errors_are_reported(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert qops_cli.main(["run", "--local", str(tmp_path)]) == 2
    assert "missing algorithm.yaml" in capsys.readouterr().err
    assert qops_cli.main(["run", "--local", str(tmp_path), "--set", "novalue"]) == 2
    assert "--set expects key=value" in capsys.readouterr().err


@pytest.mark.parametrize("kind", ["sampling", "variational"])
def test_new_algorithm_scaffold_is_valid(
    tmp_path: Path, kind: str, capsys: pytest.CaptureFixture[str]
) -> None:
    assert (
        qops_cli.main(["new", "algorithm", f"demo_{kind}", "--kind", kind, "--dir", str(tmp_path)])
        == 0
    )
    created = tmp_path / f"demo_{kind}"
    assert load_algorithm(created).kind.value == kind
    run = [
        "run",
        "--local",
        str(created),
        "--maxiter",
        "5",
        "--state-dir",
        str(tmp_path / "s"),
        "--json",
    ]
    assert qops_cli.main(run) == 0
    capsys.readouterr()
    assert (
        qops_cli.main(["new", "algorithm", f"demo_{kind}", "--kind", kind, "--dir", str(tmp_path)])
        == 2
    )
    assert (
        qops_cli.main(["new", "algorithm", "Bad-Name", "--kind", kind, "--dir", str(tmp_path)]) == 2
    )
