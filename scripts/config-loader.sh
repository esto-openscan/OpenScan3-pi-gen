#!/bin/bash
# shellcheck shell=bash

load_build_config() {
    local common_env="$1"
    local camera_env="$2"

    if [ ! -f "$common_env" ]; then
        echo "Common build environment '$common_env' not found" >&2
        exit 1
    fi

    if [ ! -f "$camera_env" ]; then
        echo "Camera configuration '$camera_env' not found" >&2
        exit 1
    fi

    # Load shared defaults
    # shellcheck disable=SC1090
    source "$common_env"

    local base_stage_list="${STAGE_LIST}"
    local base_target_hostname="${TARGET_HOSTNAME}"
    local base_img_name_prefix="${IMG_NAME_PREFIX}"

    unset STAGE_LIST TARGET_HOSTNAME IMG_NAME_PREFIX

    # Load camera-specific overrides
    # shellcheck disable=SC1090
    source "$camera_env"

    if [ -z "${CAMERA_TYPE:-}" ]; then
        echo "CAMERA_TYPE not defined in '$camera_env'" >&2
        exit 1
    fi

    if [ -z "${IMG_NAME_SUFFIX:-}" ]; then
        echo "IMG_NAME_SUFFIX not defined in '$camera_env'" >&2
        exit 1
    fi

    local camera_stage_list="${STAGE_LIST:-}"
    local camera_target_hostname="${TARGET_HOSTNAME:-$base_target_hostname}"

    STAGE_LIST="${base_stage_list}"
    if [ -n "${camera_stage_list}" ]; then
        STAGE_LIST+=" ${camera_stage_list}"
    fi

    TARGET_HOSTNAME="${camera_target_hostname}"
    IMG_NAME="${base_img_name_prefix}_${IMG_NAME_SUFFIX}"
}
