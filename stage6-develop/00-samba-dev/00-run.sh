#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

install -d -m 755 "${ROOTFS_DIR}/opt/openscan3-client"

on_chroot <<'EOF'
set -e

install -d -m 2775 /opt/openscan3-client
chown openscan:openscan /opt/openscan3-client

cat <<'CONF' >> /etc/samba/smb.conf

[openscan3-client]
   comment = OpenScan3 Client SPA (read/write)
   path = /opt/openscan3-client
   browseable = yes
   guest ok = yes
   read only = no
   writeable = yes
   force user = openscan
   force group = openscan
   create mask = 0664
   directory mask = 2775
CONF

systemctl restart smbd nmbd || true
EOF
