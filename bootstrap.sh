#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/workspace/home}"
export APP_BRANCH="${APP_BRANCH:-codex/clouddeploy}"
export CHECK_INTERVAL="${CHECK_INTERVAL:-60}"

mkdir -p "${HOME}" /workspace

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
from pathlib import Path

payload = os.environ["HUB_RUNTIME_ENV_B64"]
Path("/workspace/runtime.env").write_bytes(base64.b64decode(payload))
PY
  set -a
  . /workspace/runtime.env
  set +a
fi

repo_url="https://x-access-token:${GH_REPO_TOKEN}@github.com/rrabeloparreira/tutory-automations.git"

if [ ! -d /workspace/app/.git ]; then
  git clone --depth 1 --branch "${APP_BRANCH}" "${repo_url}" /workspace/app
fi

cd /workspace/app
exec /workspace/app/cloud/hub/run_hub.sh
