#!/bin/bash
set -euo pipefail

PI_GEN_DIR="pi-gen"
CONFIG_DIR="build-configs"
COMMON_ENV="${CONFIG_DIR}/base.env"
CONFIG_HELPER="scripts/config-loader.sh"
BUILD_DOCKER_SCRIPT="${PI_GEN_DIR}/build-docker.sh"
PROJECT_ROOT="${PWD}"
ENABLE_STAGE6=0

if [ ! -d "${PI_GEN_DIR}" ]; then
    echo "Expected pi-gen submodule in '${PI_GEN_DIR}'" >&2
    exit 1
fi

if [ ! -x "${BUILD_DOCKER_SCRIPT}" ]; then
    echo "Docker build script not found at '${BUILD_DOCKER_SCRIPT}'" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required but not installed or not on PATH" >&2
    exit 1
fi

if [ ! -d "${CONFIG_DIR}" ]; then
    echo "Expected build configuration directory '${CONFIG_DIR}'" >&2
    exit 1
fi

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

HOST_WORK_DIR="${HOST_WORK_DIR:-${PI_GEN_DIR}/work}"
HOST_DEPLOY_DIR="${HOST_DEPLOY_DIR:-${PI_GEN_DIR}/deploy}"
HOST_APT_CACHE_DIR="${HOST_APT_CACHE_DIR:-${PWD}/.cache/pi-gen/apt}"

mkdir -p "${HOST_WORK_DIR}" "${HOST_DEPLOY_DIR}" "${HOST_APT_CACHE_DIR}"

HOST_WORK_DIR=$(realpath "${HOST_WORK_DIR}")
HOST_DEPLOY_DIR=$(realpath "${HOST_DEPLOY_DIR}")
HOST_APT_CACHE_DIR=$(realpath "${HOST_APT_CACHE_DIR}")

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
                CAM_CONFIGS+=("${CONFIG_DIR}/${arg}.env")
                ;;
        esac
    done
fi

if [ "${#CAM_CONFIGS[@]}" -eq 0 ]; then
    mapfile -t CAM_CONFIGS < <(find "${CONFIG_DIR}" -maxdepth 1 -type f -name '*.env' ! -name 'base.env' | sort)
fi

if [ "${#CAM_CONFIGS[@]}" -eq 0 ]; then
    echo "No build configuration files found under '${CONFIG_DIR}'" >&2
    exit 1
fi

if [ "${#CAM_CONFIGS[@]}" -eq 0 ]; then
    echo "No camera configuration files found." >&2
    exit 1
fi

cleanup_configs=()
cleanup() {
    for cfg in "${cleanup_configs[@]}"; do
        [ -f "$cfg" ] && rm -f "$cfg"
    done
}
trap cleanup EXIT

for cam_config in "${CAM_CONFIGS[@]}"; do
    if [ "$cam_config" = "${COMMON_ENV}" ]; then
        continue
    fi

    if [ ! -f "$cam_config" ]; then
        echo "Configuration file '$cam_config' not found" >&2
        exit 1
    fi

    load_build_config "${COMMON_ENV}" "$cam_config"

    if [ -z "${IMG_NAME:-}" ]; then
        echo "IMG_NAME not defined after loading '$cam_config'" >&2
        exit 1
    fi

    if [ -z "${STAGE_LIST:-}" ]; then
        echo "STAGE_LIST not defined after loading '$cam_config'" >&2
        exit 1
    fi

    if [ "$ENABLE_STAGE6" -eq 1 ]; then
        STAGE_LIST="${STAGE_LIST} stage6-develop"
        STAGE_LIST="${STAGE_LIST# }"
    fi

    tmp_config=$(mktemp "${TMPDIR:-/tmp}/pigen-docker-config.XXXXXX")
    cleanup_configs+=("$tmp_config")

    cat "$cam_config" > "$tmp_config"
    printf '\n' >> "$tmp_config"

    read -r -a stage_items <<< "${STAGE_LIST}"
    container_stage_items=()
    docker_volume_opts=(
        "--volume=${HOST_WORK_DIR}:/pi-gen/work"
        "--volume=${HOST_DEPLOY_DIR}:/pi-gen/deploy"
        "--volume=${HOST_APT_CACHE_DIR}:/var/cache/apt"
    )

    OPENSCAN3_DIR="${PROJECT_ROOT}/OpenScan3"
    if [ -d "${OPENSCAN3_DIR}" ]; then
        OPENSCAN3_DIR=$(realpath "${OPENSCAN3_DIR}")
        docker_volume_opts+=("--volume=${OPENSCAN3_DIR}:/pi-gen/OpenScan3")
    fi

    OPENSCAN3_GIT_DIR="${PROJECT_ROOT}/.git/modules/OpenScan3"
    if [ -d "${OPENSCAN3_GIT_DIR}" ]; then
        OPENSCAN3_GIT_DIR=$(realpath "${OPENSCAN3_GIT_DIR}")
        docker_volume_opts+=("--volume=${OPENSCAN3_GIT_DIR}:/pi-gen/OpenScan3-git")
    fi

    OPENSCAN3_CLIENT_DIST="${PROJECT_ROOT}/OpenScan3-client-dist"
    if [ -d "${OPENSCAN3_CLIENT_DIST}" ]; then
        OPENSCAN3_CLIENT_DIST=$(realpath "${OPENSCAN3_CLIENT_DIST}")
        docker_volume_opts+=("--volume=${OPENSCAN3_CLIENT_DIST}:/pi-gen/OpenScan3-client-dist")
    fi

    for stage in "${stage_items[@]}"; do
        case "$stage" in
            /*)
                container_stage="$stage"
                ;;
            pi-gen/*)
                container_stage="/pi-gen/${stage#pi-gen/}"
                ;;
            *)
                container_stage="/pi-gen/${stage}"
                host_stage_path="$stage"
                host_stage_abs=$(realpath "$host_stage_path")
                docker_volume_opts+=("--volume=${host_stage_abs}:${container_stage}")
                ;;
        esac
        if [[ "$stage" == pi-gen/* ]]; then
            # ensure host path resolution relative to project root
            host_stage_abs=$(realpath "$stage")
            docker_volume_opts+=("--volume=${host_stage_abs}:${container_stage}")
        fi
        container_stage_items+=("${container_stage}")
    done
    printf 'STAGE_LIST="%s"\n' "${container_stage_items[*]}" >> "$tmp_config"
    printf 'IMG_NAME="%s"\n' "$IMG_NAME" >> "$tmp_config"
    printf 'TARGET_HOSTNAME="%s"\n' "${TARGET_HOSTNAME}" >> "$tmp_config"

    if ! grep -q '^WORK_DIR=' "$tmp_config"; then
        printf 'WORK_DIR="%s"\n' "/pi-gen/work/${IMG_NAME}" >> "$tmp_config"
    fi

    config_path=$(realpath "$tmp_config")

    docker_opts_string="${docker_volume_opts[*]}"

    echo "[Docker] Building image '${IMG_NAME}' using '${cam_config}'"
    PIGEN_DOCKER_OPTS="${docker_opts_string}" "${BUILD_DOCKER_SCRIPT}" -c "$config_path"
    echo "[Docker] Completed build for '${IMG_NAME}'"

    unset CAMERA_TYPE IMG_NAME IMG_NAME_SUFFIX STAGE_LIST TARGET_HOSTNAME WORK_DIR
    printf '\n'
done
