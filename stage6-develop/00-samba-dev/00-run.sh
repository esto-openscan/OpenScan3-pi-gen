#!/bin/bash -e

on_chroot <<'EOF'
set -e

install -d -m 2775 /opt/openscan3-dev
chown openscan:openscan /opt/openscan3-dev

cat <<'CONF' >> /etc/samba/smb.conf

[openscan-community-tasks]
   comment = OpenScan3 Community Tasks (read/write)
   path = /var/openscan3/community-tasks
   browseable = yes
   guest ok = yes
   read only = no
   writeable = yes
   force user = openscan
   force group = openscan
   create mask = 0664
   directory mask = 2775

[openscan-dev]
   comment = OpenScan3 Development (read/write)
   path = /opt/openscan3-dev
   browseable = yes
   guest ok = yes
   read only = no
   writeable = yes
   force user = openscan
   force group = openscan
   create mask = 0664
   directory mask = 2775

[openscan-logs]
   comment = OpenScan3 Logs (read-only)
   path = /var/log/openscan3
   browseable = yes
   guest ok = yes
   read only = yes
   writeable = no
   force user = openscan
   force group = openscan
   create mask = 0444
   directory mask = 0555

CONF

systemctl restart smbd nmbd || true
EOF
