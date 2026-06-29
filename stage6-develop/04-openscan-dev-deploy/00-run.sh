#!/bin/bash -e

install -m 755 -D files/usr/bin/openscan-dev "${ROOTFS_DIR}/usr/bin/openscan-dev"
install -m 644 -D files/etc/openscan3-dev/config.env "${ROOTFS_DIR}/etc/openscan3-dev/config.env"

on_chroot <<'EOF'
set -e

install -d -m 2775 /opt/openscan3-dev
chown openscan:openscan /opt/openscan3-dev

install -d -m 755 /etc/openscan3-dev
chmod 0644 /etc/openscan3-dev/config.env

install -d -m 755 /etc/systemd/system/openscan3.service.d

if command -v openscan-dev >/dev/null 2>&1; then
  openscan-dev status >/dev/null
fi
EOF
