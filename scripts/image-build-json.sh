#!/bin/bash
# shellcheck shell=bash

json_string() {
    local value="${1-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '"%s"' "$value"
}

write_image_build_json() {
    local output_file="$1"
    local image_family="$2"
    local channel="$3"
    local image_name="$4"
    local target_hostname="$5"
    local build_date="$6"
    local image_repo_commit="$7"
    local pi_gen_commit="$8"
    local pi_gen_dirty="$9"

    mkdir -p "$(dirname "$output_file")"

    {
        printf '{\n'
        printf '  "build_date": %s,\n' "$(json_string "$build_date")"
        printf '  "channel": %s,\n' "$(json_string "$channel")"
        printf '  "image": "openscan3-pi-gen",\n'
        printf '  "image_family": %s,\n' "$(json_string "$image_family")"
        printf '  "image_name": %s,\n' "$(json_string "$image_name")"
        printf '  "image_repo_commit": %s,\n' "$(json_string "$image_repo_commit")"
        printf '  "official_pi_gen_image": true,\n'
        printf '  "pi_gen_commit": %s,\n' "$(json_string "$pi_gen_commit")"
        printf '  "pi_gen_dirty": %s,\n' "$pi_gen_dirty"
        printf '  "target_hostname": %s,\n' "$(json_string "$target_hostname")"
        printf '  "vendor": "OpenScan"\n'
        printf '}\n'
    } > "$output_file"
}

generate_image_build_json() {
    local output_file="$1"
    local image_family="$2"
    local channel="$3"
    local image_name="$4"
    local target_hostname="$5"

    local build_date image_repo_commit pi_gen_commit pi_gen_dirty
    build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    image_repo_commit="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
    pi_gen_commit="$(git -C pi-gen rev-parse HEAD 2>/dev/null || printf 'unknown')"
    if git -C pi-gen diff --quiet --ignore-submodules -- 2>/dev/null; then
        pi_gen_dirty="false"
    else
        pi_gen_dirty="true"
    fi

    write_image_build_json "$output_file" \
        "$image_family" \
        "$channel" \
        "$image_name" \
        "$target_hostname" \
        "$build_date" \
        "$image_repo_commit" \
        "$pi_gen_commit" \
        "$pi_gen_dirty"
}
