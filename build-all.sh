#!/bin/bash
set -e

PI_GEN_DIR="pi-gen"
CONFIG_DIR="build-configs"
COMMON_ENV="${CONFIG_DIR}/base.env"
CONFIG_HELPER="scripts/config-loader.sh"

if [ ! -f "${COMMON_ENV}" ]; then
    echo "Missing common OpenScan base environment at '${COMMON_ENV}'" >&2
    exit 1
fi

if [ ! -f "${CONFIG_HELPER}" ]; then
    echo "Missing config helper script at '${CONFIG_HELPER}'" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_HELPER}"

if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

ENABLE_STAGE6=0

CAM_CONFIGS=()
if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
        case "$arg" in
            --with-develop)
                ENABLE_STAGE6=1
                ;;
            *.env)
                CAM_CONFIGS+=("$arg")
                ;;
            *)
                CAM_CONFIGS+=("$CONFIG_DIR/$arg.env")
                ;;
        esac
    done
fi

if [ "${#CAM_CONFIGS[@]}" -eq 0 ]; then
    mapfile -t CAM_CONFIGS < <(find "${CONFIG_DIR}" -maxdepth 1 -type f -name '*.env' ! -name 'base.env' | sort)
fi

if [ "${#CAM_CONFIGS[@]}" -eq 0 ]; then
    echo "No camera configuration files found under '${CONFIG_DIR}'" >&2
    exit 1
fi

for cam_config in "${CAM_CONFIGS[@]}"; do
    if [ "$cam_config" = "${COMMON_ENV}" ]; then
        continue
    fi

    load_build_config "${COMMON_ENV}" "$cam_config"

    STAGE_LIST_FOR_BUILD="$STAGE_LIST"
    if [ "$ENABLE_STAGE6" -eq 1 ]; then
        STAGE_LIST_FOR_BUILD="${STAGE_LIST_FOR_BUILD} stage6-develop"
        STAGE_LIST_FOR_BUILD="${STAGE_LIST_FOR_BUILD# }"
    fi

    ${SUDO:+$SUDO }CAMERA_TYPE=$CAMERA_TYPE IMG_NAME=$IMG_NAME          STAGE_LIST="$STAGE_LIST_FOR_BUILD"          TARGET_HOSTNAME="${TARGET_HOSTNAME}"          "$PI_GEN_DIR"/build.sh
done
