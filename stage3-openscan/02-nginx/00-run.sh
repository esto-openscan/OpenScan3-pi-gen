#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
FILES_DIR="${SCRIPT_DIR}/files"
CLIENT_DIST_DIR="${SCRIPT_DIR}/../../OpenScan3-client-dist"

install -m 644 -D "${FILES_DIR}/etc/nginx/sites-available/openscan3-api.conf" "${ROOTFS_DIR}/etc/nginx/sites-available/openscan3-api.conf"
install -d -m 755 "${ROOTFS_DIR}/etc/nginx/openscan3/locations-enabled"
install -m 644 -D "${FILES_DIR}/etc/nginx/openscan3/locations-enabled/60-client.conf" "${ROOTFS_DIR}/etc/nginx/openscan3/locations-enabled/60-client.conf"
install -m 644 -D "${FILES_DIR}/var/www/openscan-admin/index.php" "${ROOTFS_DIR}/var/www/openscan-admin/index.php"
install -d -m 755 "${ROOTFS_DIR}/opt/openscan3-client"
cp -a "${CLIENT_DIST_DIR}/." "${ROOTFS_DIR}/opt/openscan3-client/"

on_chroot <<'EOF'
set -e

ln -sf /etc/nginx/sites-available/openscan3-api.conf /etc/nginx/sites-enabled/default
install -d -m 755 /var/lib/openscan3/install
adduser www-data openscan || true
install -d -m 2775 /opt/openscan3-client
chown -R openscan:openscan /opt/openscan3-client

for CONF in /etc/php/*/fpm/pool.d/www.conf; do
  [ -f "${CONF}" ] || continue
  sed -i 's#^listen = .*#listen = 127.0.0.1:9000#' "${CONF}"
done

systemctl enable nginx
for SVC in /lib/systemd/system/php*-fpm.service; do
  [ -f "${SVC}" ] || continue
  systemctl enable "$(basename "${SVC}")"
  systemctl restart "$(basename "${SVC}")" || true
done
EOF
