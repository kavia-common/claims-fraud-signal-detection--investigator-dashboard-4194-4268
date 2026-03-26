#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/home/kavia/workspace/code-generation/claims-fraud-signal-detection--investigator-dashboard-4194-4268/FraudDetectionSystem"
cd "$WORKSPACE"
VENV="$WORKSPACE/.venv"

# Ensure venv exists
if [ ! -x "$VENV/bin/activate" ]; then
  echo "Error: virtualenv not found at $VENV. Please run the install step to create the venv." >&2
  exit 2
fi

# Activate venv
. "$VENV/bin/activate"

# Source .env with exported variables so tests see CELERY_TASK_ALWAYS_EAGER
if [ -f "$WORKSPACE/.env" ]; then
  set -o allexport 2>/dev/null || true
  . "$WORKSPACE/.env"
  set +o allexport 2>/dev/null || true
fi

# Create tests directory and minimal smoke tests (idempotent - overwrite)
mkdir -p tests
cat > tests/test_health.py <<'PY'
from fastapi.testclient import TestClient
from app.main import app

def test_health():
    client = TestClient(app)
    r = client.get('/health')
    assert r.status_code == 200
    assert r.json().get('status') == 'ok'
PY

cat > tests/test_celery.py <<'PY'
import os
from app.celery_app import ping_func, ping

def test_celery_ping_direct():
    assert ping_func() == 'pong'

def test_celery_task_call_when_eager():
    # Only attempt async result retrieval if eager mode is enabled
    if os.getenv('CELERY_TASK_ALWAYS_EAGER', '0') in ('1', 'true', 'True'):
        res = ping.apply_async()
        assert res.get(timeout=5) == 'pong'
    else:
        # If not eager, ensure task exists and has expected API
        assert hasattr(ping, 'apply_async')
PY

# Run pytest inside venv
python -m pytest -q tests

# Deactivate venv
deactivate || true

exit 0
