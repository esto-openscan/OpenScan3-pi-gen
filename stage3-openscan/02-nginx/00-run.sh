#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
FILES_DIR="${SCRIPT_DIR}/files"

install -m 644 -D "${FILES_DIR}/etc/nginx/sites-available/openscan3-api.conf" "${ROOTFS_DIR}/etc/nginx/sites-available/openscan3-api.conf"
install -m 644 -D "${FILES_DIR}/etc/nginx/sites-available/openscan3-admin.conf" "${ROOTFS_DIR}/etc/nginx/sites-available/openscan3-admin.conf"
install -d -m 755 "${ROOTFS_DIR}/etc/nginx/openscan3/locations-enabled"
install -m 644 -D "${FILES_DIR}/var/www/openscan-admin/index.php" "${ROOTFS_DIR}/var/www/openscan-admin/index.php"

on_chroot <<'EOF'
set -e

ln -sf /etc/nginx/sites-available/openscan3-api.conf /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/openscan3-admin.conf /etc/nginx/sites-enabled/openscan3-admin.conf
install -d -m 755 /var/lib/openscan3/install
adduser www-data openscan || true

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
