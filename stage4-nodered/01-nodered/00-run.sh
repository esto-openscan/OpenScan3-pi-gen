#!/bin/bash -e

echo "Configuring Node-RED"

# Install service unit, nginx site, and default flow into target rootfs
install -m 644 -D files/etc/systemd/system/node-red-openscan.service "${ROOTFS_DIR}/etc/systemd/system/node-red-openscan.service"
install -m 644 -D files/etc/nginx/sites-available/default "${ROOTFS_DIR}/etc/nginx/sites-available/default"
install -m 644 -D "${BASE_DIR}/../OpenScan3/flows/flows.json" "${ROOTFS_DIR}/opt/openscan3/.node-red/flows.json"
install -m 644 -D files/opt/openscan3/.node-red/settings.js "${ROOTFS_DIR}/opt/openscan3/.node-red/settings.js"
install -m 644 -D files/var/www/openscan-admin/index.php "${ROOTFS_DIR}/var/www/openscan-admin/index.php"

on_chroot <<'EOF'
set -e
set -x

# Persist log outside /var/log (export-image truncates /var/log)
install -d -m 755 /var/lib/openscan3/install
# Ensure Node-RED userDir exists and is owned by the openscan user
install -d -m 755 /opt/openscan3/.node-red
chown -R openscan:openscan /opt/openscan3

# Allow web server to access settings and trigger updater
adduser www-data openscan || true

echo "Configure php-fpm to listen on 127.0.0.1:9000"
for CONF in /etc/php/*/fpm/pool.d/www.conf; do
  if [ -f "$CONF" ]; then
    sed -i 's#^listen = .*#listen = 127.0.0.1:9000#' "$CONF"
  fi
done

echo "NodeJS Version:"
node -v
echo "npm Version:"
npm -v

echo "Install Node-RED globally via npm"
npm config set fund false
npm config set audit false
npm install -g node-red --unsafe-perm --loglevel verbose

# Install dashboard palette in the userDir as 'openscan'
runuser -u openscan -- bash -lc 'cd /opt/openscan3/.node-red && npm install --no-fund --no-audit @flowfuse/node-red-dashboard'

# Ensure nginx default site is enabled (symlink to sites-available/default)
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Enable and configure services
systemctl enable nginx
systemctl enable node-red-openscan

# Enable php-fpm (versioned service)
for SVC in /lib/systemd/system/php*-fpm.service; do
  if [ -f "$SVC" ]; then
    systemctl enable "$(basename "$SVC")"
    systemctl restart "$(basename "$SVC")" || true
  fi
done
EOF

