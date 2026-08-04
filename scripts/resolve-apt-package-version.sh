#!/bin/bash
set -euo pipefail

package="${1:?Usage: $0 <package> [sources-file] [architecture]}"
sources_file="${2:-stage3-openscan/00-base/files/etc/apt/sources.list.d/openscan.sources}"
architecture="${3:-arm64}"

if [ ! -f "${sources_file}" ]; then
    echo "APT sources file not found: ${sources_file}" >&2
    exit 1
fi

read_deb822_field() {
    local field="$1"
    awk -v key="${field}:" '$1 == key { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }' "${sources_file}"
}

uris="$(read_deb822_field "URIs")"
suites="$(read_deb822_field "Suites")"
components="$(read_deb822_field "Components")"

if [ -z "${uris}" ] || [ -z "${suites}" ] || [ -z "${components}" ]; then
    echo "Failed to read URIs, Suites, and Components from ${sources_file}" >&2
    exit 1
fi

versions=()
for uri in ${uris}; do
    uri="${uri%/}"
    for suite in ${suites}; do
        for component in ${components}; do
            for repo_arch in "${architecture}" all; do
                packages_url="${uri}/dists/${suite}/${component}/binary-${repo_arch}/Packages.gz"
                while IFS= read -r version; do
                    [ -n "${version}" ] && versions+=("${version}")
                done < <(
                    curl -fsSL "${packages_url}" |
                        gzip -dc |
                        awk -v pkg="${package}" '
                            BEGIN { RS = ""; FS = "\n" }
                            {
                                found_pkg = 0
                                version = ""
                                for (i = 1; i <= NF; i++) {
                                    if ($i == "Package: " pkg) found_pkg = 1
                                    if ($i ~ /^Version: /) {
                                        version = $i
                                        sub(/^Version: /, "", version)
                                    }
                                }
                                if (found_pkg && version != "") print version
                            }
                        '
                )
            done
        done
    done
done

if [ "${#versions[@]}" -eq 0 ]; then
    echo "Package '${package}' not found in ${sources_file} for architecture '${architecture}'" >&2
    exit 1
fi

candidate="${versions[0]}"
for version in "${versions[@]}"; do
    if dpkg --compare-versions "${version}" gt "${candidate}"; then
        candidate="${version}"
    fi
done

printf '%s\n' "${candidate}"
