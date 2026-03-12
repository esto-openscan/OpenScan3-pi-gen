#!/bin/bash -e

echo "Configuring OpenScan3 base components"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROJECT_ROOT="$(readlink -f "${SCRIPT_DIR}/../..")"
SUBMODULE_DIR="${PROJECT_ROOT}/OpenScan3"
SUBMODULE_GIT_DIR="${PROJECT_ROOT}/OpenScan3-git"
PYPROJECT_FILE="${SUBMODULE_DIR}/pyproject.toml"

if [ ! -f "${PYPROJECT_FILE}" ]; then
  echo "pyproject.toml not found at ${PYPROJECT_FILE}" >&2
  exit 1
fi

GPHOTO2_PYPI_VERSION="$(sed -n 's/^[[:space:]]*"gphoto2==\([^"]*\)".*$/\1/p' "${PYPROJECT_FILE}" | head -n 1)"
if [ -z "${GPHOTO2_PYPI_VERSION}" ]; then
  echo "gphoto2 dependency not found in ${PYPROJECT_FILE}" >&2
  exit 1
fi
PIWHEELS_INDEX_URL="https://www.piwheels.org/simple"

export GPHOTO2_PYPI_VERSION
export PIWHEELS_INDEX_URL

if [ ! -d "${SUBMODULE_GIT_DIR}" ]; then
  SUBMODULE_GIT_DIR="$(git -C "${SUBMODULE_DIR}" rev-parse --absolute-git-dir)"
fi

install -m 755 -D files/usr/local/bin/openscan3 "${ROOTFS_DIR}/usr/local/bin/openscan3"
install -m 644 -D files/etc/systemd/system/openscan3.service "${ROOTFS_DIR}/etc/systemd/system/openscan3.service"
install -m 755 -D files/usr/local/sbin/openscan3-update "${ROOTFS_DIR}/usr/local/sbin/openscan3-update"
install -m 644 -D files/etc/avahi/services/openscan3.service "${ROOTFS_DIR}/etc/avahi/services/openscan3.service"

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
for grp in camera video render plugdev input i2c spi gpio netdev; do
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

# Prepare persistent data directories for projects and community tasks
install -d -m 2775 /var/openscan3
install -d -m 2775 /var/openscan3/projects
install -d -m 2775 /var/openscan3/community-tasks
chown -R openscan:openscan /var/openscan3
setfacl -Rm g::rwX /var/openscan3
setfacl -Rdm g::rwX /var/openscan3
setfacl -Rm m::rwX /var/openscan3
setfacl -Rdm m::rwX /var/openscan3

chown -R openscan:openscan /opt/openscan3 /opt/openscan3-src

# install OpenScan3 as pip package
runuser -u openscan -- python3 -m venv --system-site-packages /opt/openscan3/venv
runuser -u openscan -- bash -c "set -e; source /opt/openscan3/venv/bin/activate && pip install --upgrade pip && pip install --extra-index-url '${PIWHEELS_INDEX_URL}' --only-binary=:all: 'gphoto2==${GPHOTO2_PYPI_VERSION}'"
runuser -u openscan -- bash -c 'cd /opt/openscan3 && source venv/bin/activate && pip install -e .'

chmod +x /usr/local/bin/openscan3
systemctl enable openscan3
systemctl enable avahi-daemon

# Allow 'openscan' to control the OpenScan3 service and read logs without a password
cat >/etc/sudoers.d/openscan-service <<'SUDOERS'
openscan ALL=(root) NOPASSWD:/usr/bin/systemctl start openscan3
openscan ALL=(root) NOPASSWD:/usr/bin/systemctl stop openscan3
openscan ALL=(root) NOPASSWD:/usr/bin/systemctl restart openscan3
openscan ALL=(root) NOPASSWD:/usr/bin/systemctl status openscan3
openscan ALL=(root) NOPASSWD:/usr/bin/journalctl -u openscan3
openscan ALL=(root) NOPASSWD:/usr/bin/journalctl -u openscan3 -n *
openscan ALL=(root) NOPASSWD:/usr/bin/journalctl -u openscan3 -f
openscan ALL=(root) NOPASSWD:/usr/bin/journalctl -u openscan3 --no-pager
openscan ALL=(root) NOPASSWD:/usr/bin/journalctl -u openscan3 --no-pager -n *
openscan ALL=(root) NOPASSWD:/usr/sbin/shutdown now
openscan ALL=(root) NOPASSWD:/usr/sbin/reboot
SUDOERS
chmod 0440 /etc/sudoers.d/openscan-service
rm -f /etc/sudoers.d/openscan-nodered

# Allow running the updater from CLI (openscan) and via web (www-data)
cat >/etc/sudoers.d/openscan-updater <<'SUDOERS'
openscan ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update
openscan ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update --branch *
openscan ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update --keep-settings
openscan ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update --branch * --keep-settings
www-data ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update
www-data ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update --branch *
www-data ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update --keep-settings
www-data ALL=(root) NOPASSWD:/usr/local/sbin/openscan3-update --branch * --keep-settings
SUDOERS
chmod 0440 /etc/sudoers.d/openscan-updater

# Allow 'openscan' to manage WiFi connections via nmcli
cat >/etc/sudoers.d/openscan-network <<'SUDOERS'
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli device wifi list
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli device wifi list *
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli device wifi rescan
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli device wifi connect *
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli connection show
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli connection show *
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli connection delete *
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli connection up *
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli connection down *
openscan ALL=(root) NOPASSWD:/usr/bin/nmcli general status
SUDOERS
chmod 0440 /etc/sudoers.d/openscan-network
EOF
