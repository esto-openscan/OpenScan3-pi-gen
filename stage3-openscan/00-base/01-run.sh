#!/bin/bash -e

echo "Configuring OpenScan3 base components"

install -m 755 -D files/usr/local/bin/openscan3 "${ROOTFS_DIR}/usr/local/bin/openscan3"
install -m 644 -D files/etc/systemd/system/openscan3.service "${ROOTFS_DIR}/etc/systemd/system/openscan3.service"

# Sync application files into the target rootfs (outside chroot)
rm -rf "${ROOTFS_DIR}/opt/openscan3"
install -d "${ROOTFS_DIR}/opt/openscan3"
rsync -av files/opt/openscan3/ "${ROOTFS_DIR}/opt/openscan3/"

on_chroot <<'EOF'
set -e

adduser --system --group --home /opt/openscan3 openscan
for grp in camera video render plugdev input i2c spi gpio; do
  groupadd -f "$grp"
  adduser openscan "$grp"
done

curl -LsSf https://astral.sh/uv/install.sh | sh
mv /root/.local/bin/uv /usr/local/bin/uv

chown -R openscan:openscan /opt/openscan3

# use this for deterministic and identical builds
#runuser -u openscan -- /usr/local/bin/uv sync --frozen --project /opt/openscan3
# use this to not hard pin package versions (will use latest compatible packages)
runuser -u openscan -- python3 -m venv --system-site-packages /opt/openscan3/venv
runuser -u openscan -- bash -c 'cd /opt/openscan3 && source venv/bin/activate && uv pip install .'


chmod +x /usr/local/bin/openscan3
systemctl enable openscan3
EOF
