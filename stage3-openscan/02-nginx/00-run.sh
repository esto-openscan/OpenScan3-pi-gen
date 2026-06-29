#!/bin/bash -e

on_chroot <<'EOF'
set -e

systemctl enable nginx
test -d /usr/share/openscan3-client
test -f /etc/nginx/sites-available/openscan3.conf
nginx -t
EOF
