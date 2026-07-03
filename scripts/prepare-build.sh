#!/bin/bash
set -euo pipefail

LOG_PREFIX="[prepare-build]"
log() { echo "${LOG_PREFIX} $*"; }
err() { echo "${LOG_PREFIX} ERROR: $*" >&2; }

usage() {
  cat <<'EOF'
Usage: scripts/prepare-build.sh [options]

Syncs the pi-gen submodule so native (non-docker) pi-gen runs have the
required upstream build scripts.

Options:
  --skip-submodules   Skip git submodule sync/update
  --skip-client       Deprecated no-op; client files are installed from .deb
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

SKIP_SUBMODULES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-submodules)
      SKIP_SUBMODULES=1
      shift
      ;;
    --skip-client)
      log "Ignoring deprecated --skip-client; openscan3-client is installed from the Debian package."
      shift
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

require_cmd git

if [[ $SKIP_SUBMODULES -eq 0 ]]; then
  log "Syncing pi-gen submodule..."
  git -C "${PROJECT_ROOT}" submodule sync pi-gen
  log "Updating pi-gen submodule..."
  git -C "${PROJECT_ROOT}" submodule update --init --checkout pi-gen
  log "Preparation complete."
else
  log "Nothing to do."
fi
