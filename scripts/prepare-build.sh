#!/bin/bash
set -euo pipefail

LOG_PREFIX="[prepare-build]"
log() { echo "${LOG_PREFIX} $*"; }
err() { echo "${LOG_PREFIX} ERROR: $*" >&2; }

usage() {
  cat <<'EOF'
Usage: scripts/prepare-build.sh [options]

Syncs git submodules and downloads the latest OpenScan3-Client SPA build so
native (non-docker) pi-gen runs have every asset required by stage3.

Options:
  --skip-submodules   Skip git submodule sync/update
  --skip-client       Skip downloading the OpenScan3-Client dist archive
  --client-repo REPO  Override GitHub repo (default: esto-openscan/OpenScan3-Client)
  --spa-zip NAME      Override asset name (default: spa.zip)
  --client-url URL    Override full download URL (takes precedence over repo/name)
  -h, --help          Show this help
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing required command: $1"
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(readlink -f "${SCRIPT_DIR}/..")"
CLIENT_DIST_DIR="${PROJECT_ROOT}/OpenScan3-client-dist"

DEFAULT_CLIENT_REPO="OpenScan-org/OpenScan3-Client"
DEFAULT_SPA_ZIP="spa.zip"

SKIP_SUBMODULES=0
SKIP_CLIENT=0
CLIENT_REPO="${CLIENT_REPO:-$DEFAULT_CLIENT_REPO}"
SPA_ZIP_NAME="${SPA_ZIP_NAME:-$DEFAULT_SPA_ZIP}"
CLIENT_URL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-submodules)
      SKIP_SUBMODULES=1
      shift
      ;;
    --skip-client)
      SKIP_CLIENT=1
      shift
      ;;
    --client-repo)
      CLIENT_REPO="$2"
      shift 2
      ;;
    --spa-zip)
      SPA_ZIP_NAME="$2"
      shift 2
      ;;
    --client-url)
      CLIENT_URL_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

CLIENT_URL="${CLIENT_URL_OVERRIDE:-"https://github.com/${CLIENT_REPO}/releases/latest/download/${SPA_ZIP_NAME}"}"

require_cmd git
require_cmd curl
require_cmd unzip

if [[ $SKIP_SUBMODULES -eq 0 ]]; then
  log "Syncing git submodules..."
  git -C "${PROJECT_ROOT}" submodule sync --recursive
  log "Updating git submodules..."
  git -C "${PROJECT_ROOT}" submodule update --init --recursive
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [[ $SKIP_CLIENT -eq 0 ]]; then
  ZIP_PATH="${TMP_DIR}/openscan3-client.zip"
  log "Downloading OpenScan3-Client SPA from ${CLIENT_URL} ..."
  curl -fsSL -o "${ZIP_PATH}" "${CLIENT_URL}"

  log "Extracting SPA archive into ${CLIENT_DIST_DIR} ..."
  rm -rf "${CLIENT_DIST_DIR}"
  mkdir -p "${CLIENT_DIST_DIR}"
  unzip -q "${ZIP_PATH}" -d "${CLIENT_DIST_DIR}"
  log "OpenScan3 client ready at ${CLIENT_DIST_DIR}"
fi

if [[ $SKIP_SUBMODULES -eq 0 || $SKIP_CLIENT -eq 0 ]]; then
  log "Preparation complete."
else
  log "Nothing to do (both steps skipped)."
fi
