#!/bin/bash -e

# Ensure drop-in directory exists inside the target rootfs
install -d -m 755 "${ROOTFS_DIR}/etc/systemd/system/openscan3.service.d"

# Provide development-only task discovery flags
cat <<'EOF' > "${ROOTFS_DIR}/etc/systemd/system/openscan3.service.d/10-dev-task-flags.conf"
[Service]
Environment="OPENSCAN_TASK_AUTODISCOVERY=1"
Environment="OPENSCAN_TASK_OVERRIDE_ON_CONFLICT=1"
EOF
