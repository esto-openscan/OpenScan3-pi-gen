#!/bin/bash -e

# Enable interactive SSH access for develop images and set a known password
# for the 'openscan' service account. These changes are intentionally
# restricted to stage6-develop builds.

on_chroot <<'EOF'
set -e

echo 'openscan:openscan' | chpasswd
systemctl enable ssh
chsh -s /bin/bash openscan
adduser openscan sudo
EOF
