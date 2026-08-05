#!/bin/bash
set -euo pipefail

PI_GEN_DIR="pi-gen"
CONFIG_DIR="build-configs"
COMMON_ENV="${CONFIG_DIR}/base.env"
CONFIG_HELPER="scripts/config-loader.sh"
IMAGE_BUILD_JSON_HELPER="scripts/image-build-json.sh"
CLEANUP_SCRIPT="scripts/cleanup.sh"
BUILD_DOCKER_SCRIPT="${PI_GEN_DIR}/build-docker.sh"
PROJECT_ROOT="${PWD}"
ENABLE_STAGE6=0
DEVELOP_ONLY=0
SKIP_CLEANUP=0

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

if [ ! -f "${IMAGE_BUILD_JSON_HELPER}" ]; then
    echo "Missing image build JSON helper script at '${IMAGE_BUILD_JSON_HELPER}'" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_HELPER}"
# shellcheck disable=SC1090
source "${IMAGE_BUILD_JSON_HELPER}"

HOST_WORK_DIR="${HOST_WORK_DIR:-${PI_GEN_DIR}/work}"
HOST_DEPLOY_DIR="${HOST_DEPLOY_DIR:-${PI_GEN_DIR}/deploy}"
HOST_APT_CACHE_DIR="${HOST_APT_CACHE_DIR:-${PWD}/.cache/pi-gen/apt}"
FINAL_DEPLOY_DIR="${FINAL_DEPLOY_DIR:-deploy}"

mkdir -p "${HOST_WORK_DIR}" "${HOST_DEPLOY_DIR}" "${HOST_APT_CACHE_DIR}" "${FINAL_DEPLOY_DIR}"

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
            --develop-only)
                ENABLE_STAGE6=1
                DEVELOP_ONLY=1
                ;;
            --skip-cleanup)
                SKIP_CLEANUP=1
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

# Offer cleanup before build (after parsing --skip-cleanup)
if [ "${SKIP_CLEANUP}" -eq 0 ] && [ -f "${CLEANUP_SCRIPT}" ]; then
    echo ""
    read -p "Do you want to clean all caches, work, deploy directories and Docker images before building? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bash "${CLEANUP_SCRIPT}"
        echo ""
    fi
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
qemu_shim_dir=""
cleanup() {
    for cfg in "${cleanup_configs[@]}"; do
        [ -f "$cfg" ] && rm -f "$cfg"
    done
    [ -n "${qemu_shim_dir}" ] && rm -rf "${qemu_shim_dir}"
}
trap cleanup EXIT

run_docker_build_variant() {
    local stage_list="$1"
    local img_name="$2"
    local target_hostname="$3"
    local cam_config="$4"
    local flavor_label="$5"
    local openscan_apt_channel="$6"
    local host_image_build_json="${HOST_WORK_DIR}/${img_name}/image-build.json"
    local container_image_build_json="/pi-gen/work/${img_name}/image-build.json"

    local tmp_config
    tmp_config=$(mktemp "${TMPDIR:-/tmp}/pigen-docker-config.XXXXXX")
    cleanup_configs+=("$tmp_config")

    cat "$cam_config" > "$tmp_config"
    printf '\n' >> "$tmp_config"

    local -a stage_items
    read -r -a stage_items <<< "$stage_list"
    local -a container_stage_items=()
    local -a docker_volume_opts=(
        "--volume=${HOST_WORK_DIR}:/pi-gen/work"
        "--volume=${HOST_DEPLOY_DIR}:/pi-gen/deploy"
        "--volume=${HOST_APT_CACHE_DIR}:/var/cache/apt"
    )

    local stage
    for stage in "${stage_items[@]}"; do
        local container_stage host_stage_path host_stage_abs
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
            host_stage_abs=$(realpath "$stage")
            docker_volume_opts+=("--volume=${host_stage_abs}:${container_stage}")
        fi
        container_stage_items+=("${container_stage}")
    done

    printf 'STAGE_LIST="%s"\n' "${container_stage_items[*]}" >> "$tmp_config"
    printf 'IMG_NAME="%s"\n' "$img_name" >> "$tmp_config"
    printf 'TARGET_HOSTNAME="%s"\n' "$target_hostname" >> "$tmp_config"
    printf 'export OPENSCAN_APT_CHANNEL="%s"\n' "$openscan_apt_channel" >> "$tmp_config"
    printf 'export OPENSCAN_IMAGE_BUILD_JSON="%s"\n' "$container_image_build_json" >> "$tmp_config"

    if ! grep -q '^WORK_DIR=' "$tmp_config"; then
        printf 'WORK_DIR="%s"\n' "/pi-gen/work/${img_name}" >> "$tmp_config"
    fi

    local config_path
    config_path=$(realpath "$tmp_config")

    if [ -d "${QEMU_BINFMT_DIR:-}" ]; then
        docker_volume_opts+=("--volume=${QEMU_BINFMT_DIR}:${QEMU_BINFMT_DIR}:ro")
    fi

    local docker_opts_string="${docker_volume_opts[*]}"
    local label_suffix=""
    if [ -n "$flavor_label" ]; then
        label_suffix=" (${flavor_label})"
    fi

    generate_image_build_json "$host_image_build_json" \
        "$CAMERA_TYPE" \
        "$openscan_apt_channel" \
        "$img_name" \
        "$target_hostname"

    echo "[Docker] Building image '${img_name}'${label_suffix} using '${cam_config}'"
    PIGEN_DOCKER_OPTS="${docker_opts_string}" "${BUILD_DOCKER_SCRIPT}" -c "$config_path"
    echo "[Docker] Completed build for '${img_name}'${label_suffix}"
}

copy_sanitized_artifacts() {
    local base_name="$1"
    local src_dir="${HOST_DEPLOY_DIR}"
    local dst_dir="${FINAL_DEPLOY_DIR}"
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

        dest="${dst_dir}/${base_name}${ext}"
        cp -f "${file}" "${dest}"
        echo "Exported $(basename "${file}") -> ${dest}"
        matched=1
    done
    shopt -u nullglob

    if [ "${matched}" -eq 0 ]; then
        echo "Warning: No artifacts matching ${base_name} found in ${src_dir}" >&2
    fi
}

if ! command -v qemu-aarch64 >/dev/null 2>&1 && command -v qemu-aarch64-static >/dev/null 2>&1; then
    qemu_shim_dir=$(mktemp -d)
    ln -s "$(which qemu-aarch64-static)" "${qemu_shim_dir}/qemu-aarch64"
    export PATH="${qemu_shim_dir}:${PATH}"
fi

DOCKER_WRAPPER="${PROJECT_ROOT}/scripts/docker-wrapper.sh"
if [ -x "${DOCKER_WRAPPER}" ] && [ -f "${PROJECT_ROOT}/pi-gen-Dockerfile" ]; then
    export DOCKER="${DOCKER_WRAPPER}"
fi

QEMU_BINFMT_DIR="/usr/libexec/qemu-binfmt"

ensure_arm64_binfmt() {
    case "$(uname -m)" in
        aarch64|arm64|arm*)
            return 0
            ;;
    esac

    local binfmt_entry="/proc/sys/fs/binfmt_misc/qemu-aarch64"
    if [ -f "${binfmt_entry}" ] \
        && grep -q '^enabled$' "${binfmt_entry}" \
        && grep -q '^flags:.*F' "${binfmt_entry}"; then
        return 0
    fi

    echo "No Docker-compatible arm64 binfmt handler found. Reinstalling it..."
    local -a docker_cmd=(docker)
    if ! docker info >/dev/null 2>&1; then
        docker_cmd=(sudo docker)
    fi
    # tonistiigi/binfmt leaves an existing qemu-aarch64 registration untouched.
    # Remove it first: otherwise a handler without the required F flag keeps
    # being reported as "already registered" and cannot be repaired.
    if ! "${docker_cmd[@]}" run --privileged --rm tonistiigi/binfmt --uninstall qemu-aarch64; then
        # No registration may exist at all. Attempt the installation either way;
        # its result and the F-flag check below remain authoritative.
        echo "Existing arm64 binfmt handler could not be removed; attempting installation anyway." >&2
    fi

    if ! "${docker_cmd[@]}" run --privileged --rm tonistiigi/binfmt --install arm64; then
        echo "Failed to install the arm64 binfmt handler with tonistiigi/binfmt." >&2
        echo "Check that the host kernel supports binfmt_misc and Docker can run privileged containers." >&2
        return 1
    fi

    if [ ! -f "${binfmt_entry}" ] \
        || ! grep -q '^enabled$' "${binfmt_entry}" \
        || ! grep -q '^flags:.*F' "${binfmt_entry}"; then
        echo "arm64 binfmt installation completed, but no enabled handler with the F flag was found." >&2
        return 1
    fi

    echo "arm64 binfmt handler is ready."
}

ensure_arm64_binfmt

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

    base_stage_list="${STAGE_LIST}"
    base_img_name="${IMG_NAME}"

    if [ "$DEVELOP_ONLY" -eq 1 ]; then
        build_stage_lists=("${base_stage_list} stage6-develop")
        build_img_names=("${base_img_name}_DEVELOP")
        build_labels=("develop")
        build_channels=("nightly")
    else
        build_stage_lists=("${base_stage_list}")
        build_img_names=("${base_img_name}")
        build_labels=("")
        build_channels=("stable")
    fi

    if [ "$ENABLE_STAGE6" -eq 1 ] && [ "$DEVELOP_ONLY" -eq 0 ]; then
        build_stage_lists+=("${base_stage_list} stage6-develop")
        build_img_names+=("${base_img_name}_DEVELOP")
        build_labels+=("develop")
        build_channels+=("nightly")
    fi

    for idx in "${!build_stage_lists[@]}"; do
        run_docker_build_variant "${build_stage_lists[$idx]}" \
            "${build_img_names[$idx]}" \
            "${TARGET_HOSTNAME}" \
            "$cam_config" \
            "${build_labels[$idx]}" \
            "${build_channels[$idx]}"

        copy_sanitized_artifacts "${build_img_names[$idx]}"
    done

    unset CAMERA_TYPE IMG_NAME IMG_NAME_SUFFIX STAGE_LIST TARGET_HOSTNAME WORK_DIR
    printf '\n'
done
