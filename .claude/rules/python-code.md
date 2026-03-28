---
description: Python coding standards — docstrings, deprecation, version policy, PyTorch AMP
paths:
  - '**/*.py'
---

## Docstring Style

- **Always Google style (Napoleon)** — no exceptions unless the user explicitly requests otherwise
- Never switch to NumPy style based on project type, existing code, or own judgement
- Every public function/class/module needs a docstring; at least one `Examples` section per public function — omit only when the user **explicitly says to skip examples** (e.g., "no examples needed", "skip the Examples section"); a request for brevity or a "minimal" docstring does NOT qualify

## Deprecation

**Never use `warnings.warn` for deprecation** — use `pyDeprecate` exclusively:

```python
from pyDeprecate import deprecated
```

If `pyDeprecate` is not installed, add it — do not fall back to `warnings.warn`.

Both parts below are required — decorator alone is incomplete:

```python
from pyDeprecate import deprecated


@deprecated(target=new_fn, deprecated_in="X.Y", remove_in="Z.W")
def old_fn(*args, **kwargs):
    """One-line summary.

    Args:
        ...

    Examples:
        ...
    """
    ...
```

- Deprecation lifecycle: deprecate in minor release → keep for ≥1 minor cycle → remove in next major

## Python Version Policy

- Python 3.9 reached EOL Oct 2025 — minimum for new projects is 3.10 (Python 3.10 reaches EOL Oct 2026 — review this line then)
- **Before writing any Python code**: read `pyproject.toml` (or `setup.cfg`/`setup.py`) to find `requires-python`; use only syntax/APIs available in that minimum version
- Version-gated features — **read pyproject.toml first if any of these are requested**:
  - `match` statement (3.10+)
  - `TypeAlias` (3.10+)
  - `typing.ParamSpec` (3.10+)
  - `tomllib` (3.11+) — use `tomli` backport if requires-python < 3.11
  - `ExceptionGroup` (3.11+)
  - `Self` type (3.11+)
- Use `target-version = "py310"` in ruff/mypy configs for new projects

## PyTorch AMP

- `torch.cuda.amp.autocast` deprecated in PyTorch 2.4
- Use `torch.amp.autocast('cuda', ...)` and `torch.amp.GradScaler('cuda')`

## Security

- `pickle.load` / `torch.load` on external data require `weights_only=True`

## Code Quality Rules

- Type annotations on all public interfaces
- No mutable default arguments
- No broad `except:` without re-raising or logging
- No `import *` — always explicit imports
- No global mutable state — use dependency injection
- `__all__` in `__init__.py` to define public API surface
- Prefer composition over deep inheritance
