#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
FILES_DIR="${SCRIPT_DIR}/files"

install -d -m 755 "${ROOTFS_DIR}/etc/nginx/openscan3/locations-enabled"
install -m 644 -D "${FILES_DIR}/etc/nginx/openscan3/locations-enabled/60-client.conf" \
  "${ROOTFS_DIR}/etc/nginx/openscan3/locations-enabled/60-client.conf"

install -d -m 755 "${ROOTFS_DIR}/opt/openscan3-client"

on_chroot <<'EOF'
set -e

install -d -m 2775 /opt/openscan3-client
chown openscan:openscan /opt/openscan3-client

systemctl restart nginx || true
EOF
