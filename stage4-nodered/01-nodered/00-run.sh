#!/bin/bash -e

echo "Configuring Node-RED"

# Install service unit, nginx site, and Node-RED assets into target rootfs
install -m 644 -D files/etc/systemd/system/node-red-openscan.service "${ROOTFS_DIR}/etc/systemd/system/node-red-openscan.service"
install -m 644 -D files/etc/nginx/sites-available/default "${ROOTFS_DIR}/etc/nginx/sites-available/default"
install -d -m 755 "${ROOTFS_DIR}/opt/openscan3/node-red"
install -m 644 -D files/var/www/openscan-admin/index.php "${ROOTFS_DIR}/var/www/openscan-admin/index.php"

on_chroot <<'EOF'
set -e
set -x

# Persist log outside /var/log (export-image truncates /var/log)
install -d -m 755 /var/lib/openscan3/install
# Ensure Node-RED directory exists and maintain ownership
install -d -m 755 /opt/openscan3/node-red
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

# Install listed palettes in the userDir as 'openscan'
runuser -u openscan -- bash -lc 'set -e; cd /opt/openscan3/node-red; if [[ -f nodered-plugins.txt ]]; then while IFS= read -r raw || [[ -n "${raw}" ]]; do plugin=$(printf "%s" "${raw}" | tr -d "\r" | xargs); [[ -z "${plugin}" || "${plugin:0:1}" == "#" ]] && continue; npm install --no-fund --no-audit "${plugin}"; done < nodered-plugins.txt; fi'

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

