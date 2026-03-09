#!/bin/bash
set -e

PI_GEN_DIR="pi-gen"
CONFIG_DIR="build-configs"
COMMON_ENV="${CONFIG_DIR}/base.env"
CONFIG_HELPER="scripts/config-loader.sh"
CLEANUP_SCRIPT="scripts/cleanup.sh"
FINAL_DEPLOY_DIR="${FINAL_DEPLOY_DIR:-deploy}"

if [ ! -f "${COMMON_ENV}" ]; then
    echo "Missing common OpenScan base environment at '${COMMON_ENV}'" >&2
    exit 1
fi

if [ ! -f "${CONFIG_HELPER}" ]; then
    echo "Missing config helper script at '${CONFIG_HELPER}'" >&2
    exit 1
fi

# Offer cleanup before build
SKIP_CLEANUP=0
if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
        case "$arg" in
            --skip-cleanup)
                SKIP_CLEANUP=1
                ;;
        esac
    done
fi

if [ "${SKIP_CLEANUP}" -eq 0 ] && [ -f "${CLEANUP_SCRIPT}" ]; then
    echo ""
    read -p "Do you want to clean all caches, work, deploy directories and Docker images before building? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bash "${CLEANUP_SCRIPT}"
        echo ""
    fi
fi

# shellcheck disable=SC1090
source "${CONFIG_HELPER}"

if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

copy_sanitized_artifacts() {
    local flavor_suffix="${1:-}"
    local src_dir="${PI_GEN_DIR}/deploy"
    local dst_dir="${FINAL_DEPLOY_DIR}"
    local base_name="${IMG_NAME}"
    local owner="${SUDO_USER:-$USER}"
    local matched=0
    local file ext dest

    mkdir -p "${dst_dir}"

    shopt -s nullglob
    for file in "${src_dir}"/*-"${base_name}"*; do
        case "${file}" in
            *.img.xz)
                ext=".img.xz"
                ;;
            *.img.gz)
                ext=".img.gz"
                ;;
            *.img.zip)
                ext=".img.zip"
                ;;
            *.img)
                ext=".img"
                ;;
            *.zip)
                ext=".zip"
                ;;
            *.info)
                ext=".info"
                ;;
            *.bmap)
                ext=".bmap"
                ;;
            *.bmap.gz)
                ext=".bmap.gz"
                ;;
            *.sbom)
                ext=".sbom"
                ;;
            *.sbom.xz)
                ext=".sbom.xz"
                ;;
            *.spdx.json)
                ext=".spdx.json"
                ;;
            *.spdx.json.xz)
                ext=".spdx.json.xz"
                ;;
            *.sha256)
                ext=".sha256"
                ;;
            *)
                continue
                ;;
        esac

        dest="${dst_dir}/${base_name}${flavor_suffix}${ext}"
        if [ -n "${SUDO}" ]; then
            ${SUDO} cp -f "${file}" "${dest}"
            ${SUDO} chown "${owner}:${owner}" "${dest}"
        else
            cp -f "${file}" "${dest}"
        fi
        echo "Exported $(basename "${file}") -> ${dest}"
        matched=1
    done
    shopt -u nullglob

    if [ "${matched}" -eq 0 ]; then
        echo "Warning: No artifacts matching ${base_name} found in ${src_dir}" >&2
    fi
}

ENABLE_STAGE6=0

CAM_CONFIGS=()
if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
        case "$arg" in
            --with-develop)
                ENABLE_STAGE6=1
                ;;
            --skip-cleanup)
                # Already handled above
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

    build_suffix=""
    if [ "$ENABLE_STAGE6" -eq 1 ]; then
        build_suffix="_DEVELOP"
    fi

    ${SUDO:+$SUDO }CAMERA_TYPE=$CAMERA_TYPE IMG_NAME=$IMG_NAME          STAGE_LIST="$STAGE_LIST_FOR_BUILD"          TARGET_HOSTNAME="${TARGET_HOSTNAME}"          "$PI_GEN_DIR"/build.sh

    copy_sanitized_artifacts "$build_suffix"
done
