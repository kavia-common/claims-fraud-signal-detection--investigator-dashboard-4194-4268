#!/usr/bin/env bash
set -euo pipefail
# Scaffolding step: create minimal FastAPI app, requirements, .env and start scripts
WORKSPACE="/home/kavia/workspace/code-generation/claims-fraud-signal-detection--investigator-dashboard-4194-4268/FraudDetectionSystem"
cd "$WORKSPACE"
mkdir -p "$WORKSPACE" && cd "$WORKSPACE"
mkdir -p app
# Backup existing deterministic scaffold files if present
for f in app/main.py app/celery_app.py app/__init__.py; do
  if [ -f "$f" ]; then cp -a "$f" "$f.bak.$(date +%s)"; fi
done
# Ensure package marker
cat > app/__init__.py <<'PY'
# app package for FraudDetectionSystem
PY
# FastAPI main
cat > app/main.py <<'PY'
from fastapi import FastAPI
app = FastAPI()

@app.get('/health')
def health():
    return {'status':'ok'}
PY
# Celery app with broker/backend detection and eager dev mode
cat > app/celery_app.py <<'PY'
import os
from celery import Celery

broker = os.getenv('CELERY_BROKER_URL', 'memory://')
backend = os.getenv('CELERY_RESULT_BACKEND', None)
if backend is None:
    if broker.startswith('redis://'):
        backend = broker
    else:
        # memory backend is process-local; rely on eager execution in dev
        backend = 'memory://'

celery_app = Celery('fraud', broker=broker, backend=backend)
# Allow tests/dev to run tasks synchronously when requested
if os.getenv('CELERY_TASK_ALWAYS_EAGER','0') == '1' or broker.startswith('memory://'):
    celery_app.conf.task_always_eager = True

# Helper function callable directly

def ping_func():
    return 'pong'

@celery_app.task(name='fraud.ping')
def ping():
    return ping_func()
PY
# requirements.txt with minimal lower-bounds
if [ ! -f requirements.txt ]; then
  cat > requirements.txt <<'RQ'
fastapi>=0.95
uvicorn[standard]>=0.22
celery>=5.2
redis>=4.0
kombu>=5.2
pytest>=7.0
requests>=2.0
RQ
fi
# .env defaults and secure permissions
if [ ! -f .env ]; then
  if pgrep -x redis-server >/dev/null 2>&1; then
    CELERY_BROKER_URL="redis://127.0.0.1:6379/0"
    CELERY_RESULT_BACKEND="redis://127.0.0.1:6379/1"
    CELERY_TASK_ALWAYS_EAGER=0
  else
    CELERY_BROKER_URL="memory://"
    CELERY_RESULT_BACKEND="memory://"
    CELERY_TASK_ALWAYS_EAGER=1
  fi
  cat > .env <<ENV
ENV=development
HOST=0.0.0.0
PORT=8000
CELERY_BROKER_URL=${CELERY_BROKER_URL}
CELERY_RESULT_BACKEND=${CELERY_RESULT_BACKEND}
CELERY_TASK_ALWAYS_EAGER=${CELERY_TASK_ALWAYS_EAGER}
DATABASE_URL=sqlite:///./dev.db
ENV
  chmod 600 .env
fi
# scripts: start_uvicorn and start_celery
mkdir -p scripts && chmod +x scripts
VENV_ACT="$WORKSPACE/.venv/bin/activate"
cat > scripts/start_uvicorn.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/claims-fraud-signal-detection--investigator-dashboard-4194-4268/FraudDetectionSystem"
VENV_ACT="$WORKSPACE/.venv/bin/activate"
# Source .env for runtime values
if [ -f "$WORKSPACE/.env" ]; then set -o allexport 2>/dev/null || true; . "$WORKSPACE/.env"; set +o allexport 2>/dev/null || true; fi
# Activate venv explicitly
if [ -f "$VENV_ACT" ]; then . "$VENV_ACT"; fi
exec uvicorn app.main:app --host "${HOST:-0.0.0.0}" --port "${PORT:-8000}"
SH
chmod +x scripts/start_uvicorn.sh
cat > scripts/start_celery.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/claims-fraud-signal-detection--investigator-dashboard-4194-4268/FraudDetectionSystem"
VENV_ACT="$WORKSPACE/.venv/bin/activate"
if [ -f "$WORKSPACE/.env" ]; then set -o allexport 2>/dev/null || true; . "$WORKSPACE/.env"; set +o allexport 2>/dev/null || true; fi
if [ -f "$VENV_ACT" ]; then . "$VENV_ACT"; fi
# Only start a separate worker if broker is not memory:// (memory backend is process-local)
if echo "${CELERY_BROKER_URL:-memory://}" | grep -q '^memory://'; then
  echo 'Memory broker configured; run tasks in eager mode (no separate worker)'
  exit 0
fi
exec celery -A app.celery_app:celery_app worker --loglevel=info
SH
chmod +x scripts/start_celery.sh
# .gitignore: ensure .env ignored
if [ ! -f .gitignore ]; then
  cat > .gitignore <<GI
.venv/
__pycache__/
*.pyc
dev.db
.env
GI
else
  if ! grep -q '^\.env$' .gitignore 2>/dev/null; then echo '.env' >> .gitignore; fi
fi
exit 0
