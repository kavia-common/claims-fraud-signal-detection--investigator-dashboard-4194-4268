#!/usr/bin/env bash
set -euo pipefail

# Validation script: start uvicorn, optionally start celery worker (when redis broker),
# exercise /health, call ping directly, publish a task if cross-process results supported,
# and perform robust cleanup (TERM, wait, KILL fallback). Sources .env and activates venv.

WORKSPACE="/home/kavia/workspace/code-generation/claims-fraud-signal-detection--investigator-dashboard-4194-4268/FraudDetectionSystem"
cd "$WORKSPACE"
VENV="$WORKSPACE/.venv"
if [ ! -f "$VENV/bin/activate" ]; then echo "venv not found at $VENV; ensure prior steps created it" >&2; exit 2; fi
. "$VENV/bin/activate"
# Source .env (export all variables) if present
if [ -f "$WORKSPACE/.env" ]; then set -o allexport 2>/dev/null || true; . "$WORKSPACE/.env"; set +o allexport 2>/dev/null || true; fi

HOST=${HOST:-0.0.0.0}
PORT=${PORT:-8000}
UV_LOG=/tmp/uvicorn.log
CEL_LOG=/tmp/celery.log
: > "$UV_LOG"
: > "$CEL_LOG"
PIDS=()

cleanup() {
  # Iterate over PIDS in reverse to try to kill children before parents
  for pid in "${PIDS[@]:-}"; do
    if [ -z "$pid" ]; then continue; fi
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -TERM "$pid" >/dev/null 2>&1 || true
      for i in 1 5; do
        if kill -0 "$pid" >/dev/null 2>&1; then sleep 1; else break; fi
      done
      if kill -0 "$pid" >/dev/null 2>&1; then kill -KILL "$pid" >/dev/null 2>&1 || true; fi
    fi
  done
}
trap cleanup EXIT

# Start uvicorn in background
nohup uvicorn app.main:app --host "$HOST" --port "$PORT" >"$UV_LOG" 2>&1 &
UV_PID=$!
PIDS+=("$UV_PID")

# Wait for HTTP readiness
READY=0
for i in $(seq 1 15); do
  if curl -sS "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q 'ok'; then READY=1; break; fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then echo 'uvicorn not ready' >&2; tail -n 200 "$UV_LOG" >&2; exit 6; fi

# Direct ping invocation (calls ping_func defined in app.celery_app)
python - <<'PY'
from app.celery_app import ping_func
try:
    out = ping_func()
    print('ping-direct:', out)
except Exception as e:
    import sys
    print('ping-direct invocation failed:', e, file=sys.stderr)
    raise
PY

# Determine if broker supports cross-process results (redis)
BROKER=${CELERY_BROKER_URL:-}
BACKEND=${CELERY_RESULT_BACKEND:-}

if echo "$BROKER" | grep -q '^redis://' ; then
  # Start a separate celery worker and wait for readiness by publishing a task
  nohup celery -A app.celery_app:celery_app worker --loglevel=info >"$CEL_LOG" 2>&1 &
  CEL_PID=$!
  PIDS+=("$CEL_PID")
  # Give worker some time to boot
  sleep 5
  # Publish task and wait for result with timeout
  python - <<'PY'
from app.celery_app import ping
import sys
try:
    res = ping.apply_async()
    out = res.get(timeout=15)
    print('task-result-via-celery:', out)
except Exception as e:
    print('celery async invocation failed:', e)
    # Print recent logs to aid debugging
    try:
        with open('/tmp/celery.log') as f:
            print('\n--- celery.log (tail 200) ---')
            print('\n'.join(f.read().splitlines()[-200:]))
    except Exception:
        pass
    raise
PY
else
  echo 'Broker is memory or unsupported for cross-process results; skipping separate worker test'
fi

echo 'validation: success'
deactivate || true
exit 0
