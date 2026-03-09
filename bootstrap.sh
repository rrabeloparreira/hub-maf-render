#!/usr/bin/env bash
set -euo pipefail

export RUNTIME_ROOT="${RUNTIME_ROOT:-/tmp/hub-maf}"
export HOME="${HOME:-${RUNTIME_ROOT}/home}"
export APP_BRANCH="${APP_BRANCH:-codex/clouddeploy}"
export CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
export VENV_DIR="${VENV_DIR:-${RUNTIME_ROOT}/venv}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${RUNTIME_ROOT}/pip-cache}"
APP_DIR="${RUNTIME_ROOT}/app"

mkdir -p "${HOME}" "${RUNTIME_ROOT}"

if [ -z "${GH_REPO_TOKEN:-}" ]; then
  echo "GH_REPO_TOKEN is required" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates git
  rm -rf /var/lib/apt/lists/*
fi

if [ -n "${HUB_RUNTIME_ENV_B64:-}" ]; then
  python3 - <<'PY'
import base64
import os
import shlex
from pathlib import Path

runtime_root = Path(os.environ["RUNTIME_ROOT"])
payload = os.environ["HUB_RUNTIME_ENV_B64"]
env_path = runtime_root / "runtime.env"
shell_path = runtime_root / "runtime.sh"
env_path.write_bytes(base64.b64decode(payload))

exports = []
for raw_line in env_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    if not key:
        continue
    exports.append(f"export {key}={shlex.quote(value)}")

shell_path.write_text("\n".join(exports) + "\n", encoding="utf-8")
PY
  set -a
  . "${RUNTIME_ROOT}/runtime.sh"
  set +a
fi

repo_url="https://x-access-token:${GH_REPO_TOKEN}@github.com/rrabeloparreira/tutory-automations.git"

if [ ! -d "${APP_DIR}/.git" ]; then
  git clone \
    --depth 1 \
    --filter=blob:none \
    --single-branch \
    --no-tags \
    --branch "${APP_BRANCH}" \
    "${repo_url}" \
    "${APP_DIR}"
fi

cd "${APP_DIR}"
exec "${APP_DIR}/cloud/hub/run_hub.sh"
