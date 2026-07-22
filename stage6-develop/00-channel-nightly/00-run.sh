#!/bin/bash -e

echo "Configuring OpenScan3 develop image update channel"

cat > "${ROOTFS_DIR}/etc/apt/sources.list.d/openscan.sources" <<'EOF'
Types: deb
URIs: https://firmware.openscan.eu/apt
Suites: nightly
Components: main
Signed-By: /usr/share/keyrings/openscan-nightly-archive-keyring.gpg
EOF

on_chroot <<'EOF'
set -e

test -f /usr/share/keyrings/openscan-nightly-archive-keyring.gpg
apt-get update
openscan-updater channel --json
EOF
