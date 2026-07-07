#!/bin/bash -e

echo "Configuring OpenScan3 base components"

OPENSCAN_APT_CHANNEL="${OPENSCAN_APT_CHANNEL:-stable}"
case "${OPENSCAN_APT_CHANNEL}" in
  stable)
    OPENSCAN_APT_KEYRING="/usr/share/keyrings/openscan-stable-archive-keyring.gpg"
    ;;
  nightly)
    OPENSCAN_APT_KEYRING="/usr/share/keyrings/openscan-nightly-archive-keyring.gpg"
    ;;
  *)
    echo "Unsupported OPENSCAN_APT_CHANNEL: ${OPENSCAN_APT_CHANNEL}" >&2
    exit 1
    ;;
esac

install -m 644 -D files/usr/share/keyrings/openscan-stable-archive-keyring.gpg "${ROOTFS_DIR}/usr/share/keyrings/openscan-stable-archive-keyring.gpg"
install -m 644 -D files/usr/share/keyrings/openscan-nightly-archive-keyring.gpg "${ROOTFS_DIR}/usr/share/keyrings/openscan-nightly-archive-keyring.gpg"
install -m 644 -D files/etc/avahi/services/openscan3.service "${ROOTFS_DIR}/etc/avahi/services/openscan3.service"

OPENSCAN_IMAGE_BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OPENSCAN_IMAGE_REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
OPENSCAN_PI_GEN_COMMIT="$(git -C pi-gen rev-parse HEAD 2>/dev/null || printf 'unknown')"
OPENSCAN_PI_GEN_DIRTY="$(
  if git -C pi-gen diff --quiet --ignore-submodules -- 2>/dev/null; then
    printf 'false'
  else
    printf 'true'
  fi
)"

install -d -m 0755 "${ROOTFS_DIR}/etc/openscan3"
OPENSCAN_IMAGE_BUILD_DATE="$OPENSCAN_IMAGE_BUILD_DATE" \
OPENSCAN_IMAGE_REPO_COMMIT="$OPENSCAN_IMAGE_REPO_COMMIT" \
OPENSCAN_PI_GEN_COMMIT="$OPENSCAN_PI_GEN_COMMIT" \
OPENSCAN_PI_GEN_DIRTY="$OPENSCAN_PI_GEN_DIRTY" \
OPENSCAN_APT_CHANNEL="$OPENSCAN_APT_CHANNEL" \
CAMERA_TYPE="${CAMERA_TYPE:-unknown}" \
IMG_NAME="${IMG_NAME:-unknown}" \
TARGET_HOSTNAME="${TARGET_HOSTNAME:-openscan}" \
python3 - <<'PY' > "${ROOTFS_DIR}/etc/openscan3/image-build.json"
import json
import os

payload = {
    "vendor": "OpenScan",
    "image": "openscan3-pi-gen",
    "official_pi_gen_image": True,
    "image_family": os.environ["CAMERA_TYPE"],
    "channel": os.environ["OPENSCAN_APT_CHANNEL"],
    "image_name": os.environ["IMG_NAME"],
    "target_hostname": os.environ["TARGET_HOSTNAME"],
    "build_date": os.environ["OPENSCAN_IMAGE_BUILD_DATE"],
    "image_repo_commit": os.environ["OPENSCAN_IMAGE_REPO_COMMIT"],
    "pi_gen_commit": os.environ["OPENSCAN_PI_GEN_COMMIT"],
    "pi_gen_dirty": os.environ["OPENSCAN_PI_GEN_DIRTY"] == "true",
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY

cat > "${ROOTFS_DIR}/etc/apt/sources.list.d/openscan.sources" <<EOF
Types: deb
URIs: https://firmware.openscan.eu/apt
Suites: ${OPENSCAN_APT_CHANNEL}
Components: main
Signed-By: ${OPENSCAN_APT_KEYRING}
EOF

rm -rf "${ROOTFS_DIR}/opt/openscan3-src"

on_chroot <<'EOF'
set -e

apt-get update
apt-get install -y \
  openscan3-system-config \
  openscan3-updater \
  openscan3-firmware \
  openscan3-client

# Allow the default interactive user (if present) to edit settings without sudo
if id -u pi >/dev/null 2>&1; then
  adduser pi openscan || true
fi

systemctl enable avahi-daemon

# Clean up legacy sudoers files (permissions now handled via polkit / group membership)
rm -f /etc/sudoers.d/openscan-service
rm -f /etc/sudoers.d/openscan-nodered
rm -f /etc/sudoers.d/openscan-network

test -f /usr/share/keyrings/openscan-stable-archive-keyring.gpg
test -f /usr/share/keyrings/openscan-nightly-archive-keyring.gpg
test -f /etc/apt/sources.list.d/openscan.sources
dpkg-query -W openscan3-system-config openscan3-updater openscan3-firmware openscan3-client
if command -v nginx >/dev/null 2>&1; then
  nginx -t
fi
EOF
