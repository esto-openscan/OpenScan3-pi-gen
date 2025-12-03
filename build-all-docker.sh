#!/bin/bash
set -euo pipefail

PI_GEN_DIR="pi-gen"
CONFIG_DIR="camera-configs"
BUILD_DOCKER_SCRIPT="${PI_GEN_DIR}/build-docker.sh"
PROJECT_ROOT="${PWD}"

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
    echo "Expected camera configuration directory '${CONFIG_DIR}'" >&2
    exit 1
fi

HOST_WORK_DIR="${HOST_WORK_DIR:-${PI_GEN_DIR}/work}"
HOST_DEPLOY_DIR="${HOST_DEPLOY_DIR:-${PI_GEN_DIR}/deploy}"
HOST_APT_CACHE_DIR="${HOST_APT_CACHE_DIR:-${PWD}/.cache/pi-gen/apt}"

mkdir -p "${HOST_WORK_DIR}" "${HOST_DEPLOY_DIR}" "${HOST_APT_CACHE_DIR}"

HOST_WORK_DIR=$(realpath "${HOST_WORK_DIR}")
HOST_DEPLOY_DIR=$(realpath "${HOST_DEPLOY_DIR}")
HOST_APT_CACHE_DIR=$(realpath "${HOST_APT_CACHE_DIR}")

if [ "$#" -gt 0 ]; then
    mapfile -t CAM_CONFIGS < <(
        for arg in "$@"; do
            if [[ ${arg} == *.env ]]; then
                printf '%s\n' "$arg"
            else
                printf '%s/%s.env\n' "${CONFIG_DIR}" "$arg"
            fi
        done
    )
else
    mapfile -t CAM_CONFIGS < <(find "${CONFIG_DIR}" -maxdepth 1 -type f -name '*.env' | sort)
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
    if [ ! -f "$cam_config" ]; then
        echo "Configuration file '$cam_config' not found" >&2
        exit 1
    fi

    # shellcheck disable=SC1090
    source "$cam_config"

    if [ -z "${IMG_NAME:-}" ]; then
        echo "IMG_NAME not defined in '$cam_config'" >&2
        exit 1
    fi

    if [ -z "${STAGE_LIST:-}" ]; then
        echo "STAGE_LIST not defined in '$cam_config'" >&2
        exit 1
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

    if ! grep -q '^TARGET_HOSTNAME=' "$tmp_config"; then
        printf 'TARGET_HOSTNAME="%s"\n' "${TARGET_HOSTNAME:-openscan3-alpha}" >> "$tmp_config"
    fi

    if ! grep -q '^WORK_DIR=' "$tmp_config"; then
        printf 'WORK_DIR="%s"\n' "/pi-gen/work/${IMG_NAME}" >> "$tmp_config"
    fi

    config_path=$(realpath "$tmp_config")

    docker_opts_string="${docker_volume_opts[*]}"

    echo "[Docker] Building image '${IMG_NAME}' using '${cam_config}'"
    PIGEN_DOCKER_OPTS="${docker_opts_string}" "${BUILD_DOCKER_SCRIPT}" -c "$config_path"
    echo "[Docker] Completed build for '${IMG_NAME}'"

    unset CAMERA_TYPE IMG_NAME STAGE_LIST TARGET_HOSTNAME WORK_DIR
    printf '\n'
done
