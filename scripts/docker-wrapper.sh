#!/bin/bash
set -euo pipefail

REAL_DOCKER=$(command -v docker)
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
OVERRIDE_DOCKERFILE="${SCRIPT_DIR}/../pi-gen-Dockerfile"

if [ "$1" = "build" ] && [ -f "${OVERRIDE_DOCKERFILE}" ]; then
    exec "${REAL_DOCKER}" build --file "${OVERRIDE_DOCKERFILE}" "${@:2}"
fi

exec "${REAL_DOCKER}" "$@"
