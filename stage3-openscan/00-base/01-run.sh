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
install -d -m 0755 "${ROOTFS_DIR}/etc/openscan3"

if [ -n "${OPENSCAN_IMAGE_BUILD_JSON:-}" ] && [ -f "${OPENSCAN_IMAGE_BUILD_JSON}" ]; then
  install -m 644 "${OPENSCAN_IMAGE_BUILD_JSON}" "${ROOTFS_DIR}/etc/openscan3/image-build.json"
else
  echo "Skipping image-build.json: OPENSCAN_IMAGE_BUILD_JSON is unset or missing"
fi

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
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold \
  openscan3-system-config \
  openscan3-updater \
  openscan3-firmware \
  openscan3-client

# Allow the default interactive user (if present) to edit settings without sudo
if id -u pi >/dev/null 2>&1; then
  adduser pi openscan || true
fi

systemctl enable avahi-daemon
systemctl enable openscan3.service
test "$(systemctl is-enabled openscan3.service)" = "enabled"

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
