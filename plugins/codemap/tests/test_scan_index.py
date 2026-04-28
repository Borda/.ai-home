"""Integration tests for scan-index bin script.

Verifies index creation and incremental update behaviour.

Fixture layout:
    gamma.py          — leaf module, no imports; defines func_gamma
    beta.py           — imports gamma; defines func_beta calling func_gamma
    alpha.py          — imports beta, gamma; defines func_alpha calling func_beta
    pkg/__init__.py   — empty
    pkg/delta.py      — imports alpha; defines func_delta calling func_alpha
"""

from __future__ import annotations

import json
import subprocess
import sys

from conftest import ALPHA_SRC, BETA_SRC, DELTA_SRC, GAMMA_SRC, SCAN_INDEX


def test_creates_index(tmp_path):
    """scan-index writes .cache/scan/<name>.json containing all modules."""
    (tmp_path / "gamma.py").write_text(GAMMA_SRC)
    (tmp_path / "beta.py").write_text(BETA_SRC)
    (tmp_path / "alpha.py").write_text(ALPHA_SRC)
    (tmp_path / "pkg").mkdir()
    (tmp_path / "pkg" / "__init__.py").write_text("")
    (tmp_path / "pkg" / "delta.py").write_text(DELTA_SRC)

    result = subprocess.run(
        [sys.executable, str(SCAN_INDEX), "--root", str(tmp_path)],
        capture_output=True,
        text=True,
        cwd=str(tmp_path),
    )
    assert result.returncode == 0, result.stderr

    index_path = tmp_path / ".cache" / "scan" / f"{tmp_path.name}.json"
    assert index_path.exists()
    index = json.loads(index_path.read_text())
    names = {m["name"] for m in index["modules"]}
    assert {"alpha", "beta", "gamma", "pkg", "pkg.delta"}.issubset(names)


def test_incremental_picks_up_new_file(tmp_path):
    """Adding a file after initial scan; --incremental indexes it."""
    (tmp_path / "base.py").write_text("def f(): pass\n")
    subprocess.run(
        [sys.executable, str(SCAN_INDEX), "--root", str(tmp_path)],
        capture_output=True,
        cwd=str(tmp_path),
        check=True,
    )

    (tmp_path / "new_mod.py").write_text("import base\n")
    result = subprocess.run(
        [sys.executable, str(SCAN_INDEX), "--root", str(tmp_path), "--incremental"],
        capture_output=True,
        text=True,
        cwd=str(tmp_path),
    )
    assert result.returncode == 0, result.stderr

    index_path = tmp_path / ".cache" / "scan" / f"{tmp_path.name}.json"
    index = json.loads(index_path.read_text())
    names = {m["name"] for m in index["modules"]}
    assert "new_mod" in names
