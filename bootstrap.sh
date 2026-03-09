#!/usr/bin/env bash
set -euo pipefail

export RUNTIME_ROOT="${RUNTIME_ROOT:-/tmp/hub-maf}"
export HOME="${HOME:-${RUNTIME_ROOT}/home}"
export APP_BRANCH="${APP_BRANCH:-codex/clouddeploy}"
export CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-9999}"
export VENV_DIR="${VENV_DIR:-${RUNTIME_ROOT}/venv}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${RUNTIME_ROOT}/pip-cache}"
APP_DIR="${RUNTIME_ROOT}/app"
SPARSE_CHECKOUT_FILE="${RUNTIME_ROOT}/sparse-checkout"
PLACEHOLDER_PID=""

log() {
  printf '[hub-bootstrap] %s\n' "$*" >&2
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi
  shasum -a 256 "$1" | awk '{print $1}'
}

stop_placeholder() {
  if [ -n "${PLACEHOLDER_PID}" ] && kill -0 "${PLACEHOLDER_PID}" 2>/dev/null; then
    log "Stopping placeholder HTTP server"
    kill "${PLACEHOLDER_PID}" 2>/dev/null || true
    wait "${PLACEHOLDER_PID}" 2>/dev/null || true
  fi
  PLACEHOLDER_PID=""
}

cleanup() {
  stop_placeholder
}

trap cleanup EXIT INT TERM

mkdir -p "${HOME}" "${RUNTIME_ROOT}"

cat > "${SPARSE_CHECKOUT_FILE}" <<'EOF'
/cloud/
/configs/
/generate_plan.py
/scripts/optimize_postedital_plan.py
/scripts/update_study_links_xlsx.py
/analysis/blueprints/
/analysis/concursos/
/analysis/controle_provas_pos_edital_internet.csv
/analysis/controle_provas_pos_edital_internet.md
/analysis/controle_provas_pos_edital_internet.xlsx
/analysis/ocr_slide_texts.json
/analysis/pareamento_tutory_raiox.csv
/analysis/scores_sefaz_sp_gestao.xlsx
/tutory/__init__.py
/tutory/api/
/tutory/common/
/tutory/excel/
/tutory/metas/
/tutory/optimization/
/tutory/ordem/
/tutory/plan_upload.py
/tutory/planos/
/tutory/questoes/
/tutory/web/
EOF

if [ -z "${GH_REPO_TOKEN:-}" ]; then
  echo "GH_REPO_TOKEN is required" >&2
  exit 1
fi

ensure_system_packages() {
  local missing=()
  if ! command -v git >/dev/null 2>&1; then
    missing+=(git)
  fi
  if ! python3 - <<'PY' >/dev/null 2>&1
import ensurepip  # noqa: F401
PY
  then
    missing+=(python3-venv)
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    return
  fi

  log "Installing system packages: ${missing[*]}"
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates "${missing[@]}"
  rm -rf /var/lib/apt/lists/*
}

ensure_system_packages

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

start_placeholder() {
  log "Starting placeholder HTTP server on ${HOST}:${PORT}"
  (
    cd "${RUNTIME_ROOT}"
    exec python3 -m http.server "${PORT}" --bind "${HOST}"
  ) &
  PLACEHOLDER_PID="$!"
}

ensure_python_env() {
  mkdir -p "$(dirname "${VENV_DIR}")" "${PIP_CACHE_DIR}"
  if [ ! -x "${VENV_DIR}/bin/python" ]; then
    log "Creating virtualenv"
    python3 -m venv "${VENV_DIR}"
  fi

  local req_file req_hash marker_file
  req_file="${APP_DIR}/cloud/hub/requirements.txt"
  req_hash="$(hash_file "${req_file}")"
  marker_file="${VENV_DIR}/.requirements-hash"

  if [ -f "${marker_file}" ] && [ "$(cat "${marker_file}")" = "${req_hash}" ]; then
    log "Python dependencies already cached"
    return
  fi

  log "Installing Python dependencies"
  "${VENV_DIR}/bin/pip" install --upgrade pip
  PIP_CACHE_DIR="${PIP_CACHE_DIR}" "${VENV_DIR}/bin/pip" install --no-input -r "${req_file}"
  printf '%s' "${req_hash}" > "${marker_file}"
}

repo_url="https://x-access-token:${GH_REPO_TOKEN}@github.com/rrabeloparreira/tutory-automations.git"

start_placeholder

if [ ! -d "${APP_DIR}/.git" ]; then
  log "Cloning application repository"
  git clone \
    --depth 1 \
    --filter=blob:none \
    --single-branch \
    --no-tags \
    --no-checkout \
    --branch "${APP_BRANCH}" \
    "${repo_url}" \
    "${APP_DIR}"
  git -C "${APP_DIR}" sparse-checkout init --no-cone
  cp "${SPARSE_CHECKOUT_FILE}" "${APP_DIR}/.git/info/sparse-checkout"
  git -C "${APP_DIR}" checkout "${APP_BRANCH}"
fi

ensure_python_env
stop_placeholder

cd "${APP_DIR}"
log "Handing over to cloud runner"
exec "${APP_DIR}/cloud/hub/run_hub.sh"
