import pytest

import qops_cli


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
