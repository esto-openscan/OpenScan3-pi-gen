#!/bin/bash -e

on_chroot << 'EOF'
set -e

echo "Installing OpenScan generic camera stack..."

audit_output="$(dpkg --audit)"
if [ -n "$audit_output" ]; then
  printf '%s\n' "$audit_output" >&2
  exit 1
fi
apt-get check

dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' \
  openscan3-generic-camera-stack \
  python3-libcamera \
  python3-picamera2 \
  rpicam-apps-lite | awk '{ print } $1 != "ii" { failed=1 } END { exit failed }'

if grep -q '^# BEGIN OPENSCAN CAMERA STACK$' /boot/firmware/config.txt; then
  echo "Generic camera stack must not install a boot overlay." >&2
  exit 1
fi
EOF
