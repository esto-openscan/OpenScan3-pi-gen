#!/bin/bash -e

echo "Configuring OpenScan3 base components"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROJECT_ROOT="$(readlink -f "${SCRIPT_DIR}/../..")"
SUBMODULE_DIR="${PROJECT_ROOT}/OpenScan3"
SUBMODULE_GIT_DIR="${PROJECT_ROOT}/OpenScan3-git"

if [ ! -d "${SUBMODULE_GIT_DIR}" ]; then
  SUBMODULE_GIT_DIR="$(git -C "${SUBMODULE_DIR}" rev-parse --absolute-git-dir)"
fi

install -m 755 -D files/usr/local/bin/openscan3 "${ROOTFS_DIR}/usr/local/bin/openscan3"
install -m 644 -D files/etc/systemd/system/openscan3.service "${ROOTFS_DIR}/etc/systemd/system/openscan3.service"
install -m 755 -D files/usr/local/sbin/openscan3-update "${ROOTFS_DIR}/usr/local/sbin/openscan3-update"

rm -rf "${ROOTFS_DIR}/opt/openscan3" "${ROOTFS_DIR}/opt/openscan3-src"

install -d "${ROOTFS_DIR}/opt/openscan3-src"
rsync -a --delete --exclude '.git' "${SUBMODULE_DIR}/" "${ROOTFS_DIR}/opt/openscan3-src/"

install -d "${ROOTFS_DIR}/opt/openscan3-src/.git"
rsync -a --delete "${SUBMODULE_GIT_DIR}/" "${ROOTFS_DIR}/opt/openscan3-src/.git/"
git config --file "${ROOTFS_DIR}/opt/openscan3-src/.git/config" core.worktree /opt/openscan3-src

# Create working copy (without .git) used at runtime and for editable install
install -d "${ROOTFS_DIR}/opt/openscan3"
rsync -av --delete "${ROOTFS_DIR}/opt/openscan3-src/" "${ROOTFS_DIR}/opt/openscan3/"


on_chroot <<'EOF'
set -e

adduser --system --group --home /opt/openscan3 openscan
# Add openscan user to relevant hardware groups
for grp in camera video render plugdev input i2c spi gpio; do
  groupadd -f "$grp"
  adduser openscan "$grp"
done

# Allow the default interactive user (if present) to edit settings without sudo
if id -u pi >/dev/null 2>&1; then
  adduser pi openscan || true
fi

# Allow nginx/PHP to read settings and trigger updater
if id -u www-data >/dev/null 2>&1; then
  adduser www-data openscan || true
fi


# Create settings directory and copy defaults
install -d -m 2775 /etc/openscan3
chown -R openscan:openscan /etc/openscan3
cp -a /opt/openscan3-src/settings/. /etc/openscan3/

# Ensure ownership after copy (cp -a preserves root:root from image build)
chown -R openscan:openscan /etc/openscan3

# Ensure group-writable perms and setgid on all subdirs
find /etc/openscan3 -type d -exec chmod 2775 {} +
find /etc/openscan3 -type f -exec chmod 664 {} +

# Default ACL so new files remain group-writable for 'openscan'
setfacl -Rm g::rwX /etc/openscan3
setfacl -Rdm g::rwX /etc/openscan3
setfacl -Rm m::rwX /etc/openscan3
setfacl -Rdm m::rwX /etc/openscan3

# Prepare application log directory for OpenScan3
install -d -m 2775 /var/log/openscan3
chown openscan:openscan /var/log/openscan3

chown -R openscan:openscan /opt/openscan3 /opt/openscan3-src

# install OpenScan3 as pip package
runuser -u openscan -- python3 -m venv --system-site-packages /opt/openscan3/venv
runuser -u openscan -- bash -c 'cd /opt/openscan3 && source venv/bin/activate && pip install -e .'

chmod +x /usr/local/bin/openscan3
systemctl enable openscan3

# Allow 'openscan' to control the OpenScan3 service and read logs without a password
cat >/etc/sudoers.d/openscan-nodered <<'SUDOERS'
openscan ALL=(root) NOPASSWD:/bin/systemctl start openscan3,/bin/systemctl stop openscan3,/bin/systemctl restart openscan3,/bin/systemctl status openscan3
openscan ALL=(root) NOPASSWD:/usr/bin/systemctl start openscan3,/usr/bin/systemctl stop openscan3,/usr/bin/systemctl restart openscan3,/usr/bin/systemctl status openscan3
openscan ALL=(root) NOPASSWD:/bin/journalctl -u openscan3 *,/usr/bin/journalctl -u openscan3 *
openscan ALL=(root) NOPASSWD:/sbin/shutdown,/sbin/reboot
openscan ALL=(root) NOPASSWD:/usr/sbin/shutdown,/usr/sbin/reboot
SUDOERS
chmod 0440 /etc/sudoers.d/openscan-nodered

# Allow running the updater from CLI (openscan) and via web (www-data)
cat >/etc/sudoers.d/openscan-updater <<'SUDOERS'
openscan ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update *
www-data ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update *
SUDOERS
chmod 0440 /etc/sudoers.d/openscan-updater
EOF
