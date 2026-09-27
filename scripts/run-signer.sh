#!/bin/bash
# Reads only your local .env. Keep it private: it is shell syntax and must be trusted.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
if [ ! -x .venv/bin/python ]; then
  echo "Create .venv and install './signer[test]' first; see docs/SETUP.md." >&2
  exit 2
fi
bind="${PC_BIND:-127.0.0.1}"
port="${PC_PORT:-8787}"
tls=()
if [ -n "${PC_TLS_CERTIFICATE:-}" ] && [ -n "${PC_TLS_PRIVATE_KEY:-}" ]; then
  tls=(--ssl-certfile "$PC_TLS_CERTIFICATE" --ssl-keyfile "$PC_TLS_PRIVATE_KEY")
elif [ -n "${PC_TLS_CERTIFICATE:-}" ] || [ -n "${PC_TLS_PRIVATE_KEY:-}" ]; then
  echo "Both PC_TLS_CERTIFICATE and PC_TLS_PRIVATE_KEY are required." >&2
  exit 2
elif [[ "$bind" != "127.0.0.1" && "$bind" != "::1" ]]; then
  echo "Refusing plaintext non-loopback binding. Configure TLS or use loopback behind a local HTTPS reverse proxy." >&2
  exit 2
fi
# Validate locally without printing secrets or certificate paths. Fail closed before binding.
.venv/bin/python - <<'PY'
from pocketcard_signer.signing import SignerSettings, PassSigner, SigningError
settings = SignerSettings.from_environment()
if settings is None:
    raise SystemExit('Signer is unconfigured. Fill all required PC_* values in your private .env.')
try:
    PassSigner(settings)
except SigningError:
    raise SystemExit('Signer identity/chain/key/validity check failed. Review docs/SETUP.md. No request has been accepted.')
print('Signer preflight passed. One installation, one worker; request-body logging is disabled.')
PY
# Exactly one worker: rate limit and concurrency guard are process-local.
exec .venv/bin/python -m uvicorn pocketcard_signer.api:app --host "$bind" --port "$port" \
  --workers 1 --no-access-log --no-proxy-headers --log-level warning "${tls[@]}"
