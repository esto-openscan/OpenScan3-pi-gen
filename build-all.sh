#!/bin/bash
set -e

PI_GEN_DIR="pi-gen"
CONFIG_DIR="camera-configs"

if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

if [ "$#" -gt 0 ]; then
    CAM_CONFIGS=()
    for arg in "$@"; do
        case "$arg" in
            *.env)
                CAM_CONFIGS+=("$arg")
                ;;
            *)
                CAM_CONFIGS+=("$CONFIG_DIR/$arg.env")
                ;;
        esac
    done
else
    CAM_CONFIGS=("$CONFIG_DIR"/*.env)
fi

for cam_config in "${CAM_CONFIGS[@]}"; do
    source "$cam_config"
    ${SUDO:+$SUDO }CAMERA_TYPE=$CAMERA_TYPE IMG_NAME=$IMG_NAME \
         STAGE_LIST="$STAGE_LIST" \
         "$PI_GEN_DIR"/build.sh
done