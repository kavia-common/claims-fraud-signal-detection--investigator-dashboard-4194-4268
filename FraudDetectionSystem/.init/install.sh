#!/usr/bin/env bash
set -euo pipefail
# install-dependencies: upgrade pip tooling and install requirements into project venv non-interactively
WORKSPACE="/home/kavia/workspace/code-generation/claims-fraud-signal-detection--investigator-dashboard-4194-4268/FraudDetectionSystem"
cd "$WORKSPACE"
VENV="$WORKSPACE/.venv"
if [ ! -f "$VENV/bin/activate" ]; then
  echo "error: missing venv at $VENV" >&2
  exit 3
fi
# Activate venv for all operations
. "$VENV/bin/activate"
# Ensure pip/setuptools/wheel present and upgraded (quiet, no cache)
python -m pip install --upgrade pip setuptools wheel --no-cache-dir >/dev/null 2>&1 || { echo "error: failed to upgrade pip/setuptools/wheel" >&2; deactivate || true; exit 4; }
# Install requirements if present
if [ -f requirements.txt ]; then
  python -m pip install --upgrade -r requirements.txt --no-cache-dir || { echo "error: pip install -r requirements.txt failed" >&2; deactivate || true; exit 5; }
fi
# Validate critical imports and report versions via importlib.metadata
python - <<'PY'
import sys
from importlib import import_module
missing = []
packages = ('fastapi','uvicorn','celery','redis','kombu')
for p in packages:
    try:
        import_module(p)
    except Exception as e:
        missing.append((p,str(e)))
if missing:
    for p,e in missing:
        sys.stderr.write(f'missing:{p}:{e}\n')
    sys.exit(6)
# report versions via importlib.metadata
try:
    from importlib import metadata
except Exception:
    import importlib_metadata as metadata
for p in packages:
    try:
        v = metadata.version(p)
    except Exception:
        v = 'unknown'
    print(f'{p}:{v}')
PY
# cleanup
deactivate || true
exit 0
