#!/bin/bash -e


if ls pi-gen/work/*/stage5-nodered/rootfs >/dev/null 2>&1; then
  ROOTFS_DIR=$(echo pi-gen/work/*/stage5-nodered/rootfs)
else
  ROOTFS_DIR=$(echo pi-gen/work/*/stage3-openscan/rootfs)
fi
echo "$ROOTFS_DIR"

# Service?
ls -l "$ROOTFS_DIR/etc/systemd/system/node-red.service"

# settings.js?
grep -E 'httpAdminRoot|httpNodeRoot' "$ROOTFS_DIR/opt/openscan3/.node-red/settings.js"

# Node-RED Binary?
test -x "$ROOTFS_DIR/usr/local/bin/node-red" || test -x "$ROOTFS_DIR/usr/bin/node-red" && echo "node-red binary present"

# Global Node-RED-Module (npm -g)?
test -d "$ROOTFS_DIR/usr/local/lib/node_modules/node-red" && echo "node-red module present in /usr/local"
test -d "$ROOTFS_DIR/usr/lib/node_modules/node-red" && echo "node-red module present in /usr"

# Dashboard node-red plugin in userDir?
test -d "$ROOTFS_DIR/opt/openscan3/.node-red/node_modules/@flowfuse/node-red-dashboard" && echo "dashboard installed"

# nginx-Site symlink?
ls -l "$ROOTFS_DIR/etc/nginx/sites-available/default"