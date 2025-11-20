#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

install -m 644 -D files/etc/samba/smb.conf "${ROOTFS_DIR}/etc/samba/smb.conf"
install -d -m 755 "${ROOTFS_DIR}/opt/openscan3/projects"

on_chroot <<'EOF'
set -e

systemctl enable smbd nmbd
setfacl -Rdm o::rx /opt/openscan3/projects
setfacl -Rm o::rx /opt/openscan3/projects
EOF
