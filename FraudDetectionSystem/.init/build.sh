#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/home/kavia/workspace/code-generation/claims-fraud-signal-detection--investigator-dashboard-4194-4268/FraudDetectionSystem"
cd "$WORKSPACE"
VENV="$WORKSPACE/.venv"

if [ ! -f "$VENV/bin/activate" ]; then
  >&2 echo "build: virtualenv not found at $VENV; ensure env and deps steps completed"
  exit 2
fi

# Activate venv explicitly
. "$VENV/bin/activate"

# Byte-compile project files (quiet)
python -m compileall -q . || {
  >&2 echo "build: byte-compilation failed"
  deactivate || true
  exit 3
}

# Attempt runtime imports to validate build-time correctness
python - <<'PY'
import sys
try:
    import app.main
    import app.celery_app
    print('build: imports OK')
except Exception as e:
    sys.stderr.write('build: import failed: ' + repr(e) + '\n')
    sys.exit(7)
PY

# Deactivate venv
deactivate || true
exit 0
