#!/bin/bash -e

echo "Configuring Node-RED"

# Install service unit and Node-RED assets into target rootfs
install -m 644 -D files/etc/systemd/system/node-red-openscan.service "${ROOTFS_DIR}/etc/systemd/system/node-red-openscan.service"
install -d -m 755 "${ROOTFS_DIR}/opt/openscan3/node-red"
install -m 644 -D files/etc/nginx/openscan3/locations-enabled/nodered.conf "${ROOTFS_DIR}/etc/nginx/openscan3/locations-enabled/50-nodered.conf"

on_chroot <<'EOF'
set -e
set -x

# Ensure Node-RED directory exists and maintain ownership
install -d -m 755 /opt/openscan3/node-red
chown -R openscan:openscan /opt/openscan3

echo "NodeJS Version:"
node -v
echo "npm Version:"
npm -v

echo "Install Node-RED globally via npm"
npm config set fund false
npm config set audit false
npm install -g node-red --unsafe-perm --loglevel verbose

# Install listed palettes in the userDir as 'openscan'
runuser -u openscan -- bash -lc 'set -e; cd /opt/openscan3/node-red; if [[ -f nodered-plugins.txt ]]; then while IFS= read -r raw || [[ -n "${raw}" ]]; do plugin=$(printf "%s" "${raw}" | tr -d "\r" | xargs); [[ -z "${plugin}" || "${plugin:0:1}" == "#" ]] && continue; npm install --no-fund --no-audit "${plugin}"; done < nodered-plugins.txt; fi'

# Enable Node-RED service and reload nginx if present
systemctl enable node-red-openscan
if [ -d /etc/nginx/openscan3/locations-enabled ]; then
  systemctl restart nginx || true
fi
EOF

