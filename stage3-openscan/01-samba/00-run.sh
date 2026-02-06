#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

install -m 644 -D files/etc/samba/smb.conf "${ROOTFS_DIR}/etc/samba/smb.conf"
install -d -m 2775 "${ROOTFS_DIR}/var/openscan3/projects"
install -d -m 2775 "${ROOTFS_DIR}/var/openscan3/community-tasks"

on_chroot <<'EOF'
set -e

systemctl enable smbd nmbd
install -d -m 2775 /var/openscan3/projects
install -d -m 2775 /var/openscan3/community-tasks
chown -R openscan:openscan /var/openscan3
setfacl -Rm g::rwX /var/openscan3
setfacl -Rdm g::rwX /var/openscan3
setfacl -Rm m::rwX /var/openscan3
setfacl -Rdm m::rwX /var/openscan3
EOF
