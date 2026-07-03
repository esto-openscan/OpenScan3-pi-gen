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
install -m 644 -D files/etc/polkit-1/rules.d/49-openscan.rules "${ROOTFS_DIR}/etc/polkit-1/rules.d/49-openscan.rules"

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

if ! getent group openscan >/dev/null; then
  addgroup --system openscan
fi
if ! getent passwd openscan >/dev/null; then
  adduser --system --ingroup openscan --home /var/openscan3 --no-create-home --disabled-login openscan
fi

# Add openscan user to relevant hardware groups
for grp in camera video render plugdev input i2c spi gpio netdev systemd-journal; do
  groupadd -f "$grp"
  adduser openscan "$grp"
done

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

# Create settings directory. Package postinst scripts install defaults without
# overwriting locally edited files.
install -d -m 2775 /etc/openscan3
chown -R openscan:openscan /etc/openscan3

# Ensure group-writable perms and setgid on all subdirs
find /etc/openscan3 -type d -exec chmod 2775 {} +
find /etc/openscan3 -type f -exec chmod 664 {} +

# Default ACL so new files remain group-writable for 'openscan'
setfacl -Rm g::rwX /etc/openscan3
setfacl -Rdm g::rwX /etc/openscan3
setfacl -Rm m::rwX /etc/openscan3
setfacl -Rdm m::rwX /etc/openscan3

# Prepare application log directory for OpenScan3
install -d -m 2775 /var/log/openscan3
chown openscan:openscan /var/log/openscan3

# Prepare persistent data directories for projects and community tasks
install -d -m 2775 /var/openscan3
install -d -m 2775 /var/openscan3/projects
install -d -m 2775 /var/openscan3/community-tasks
chown -R openscan:openscan /var/openscan3
setfacl -Rm g::rwX /var/openscan3
setfacl -Rdm g::rwX /var/openscan3
setfacl -Rm m::rwX /var/openscan3
setfacl -Rdm m::rwX /var/openscan3

systemctl enable openscan3
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
