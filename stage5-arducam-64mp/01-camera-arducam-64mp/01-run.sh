#!/bin/bash -e

on_chroot << 'EOF'
set -e

echo "Configuring Arducam 64MP camera..."

hold_installed_camera_packages() {
  protected_patterns='libcamera* rpicam* librpicam* python3-libcamera python3-picamera2 python3-kms++ arducam* pivariety*'
  held_packages="$(
    for pattern in $protected_patterns; do
      dpkg-query -W -f='${binary:Package}\n' "$pattern" 2>/dev/null || true
    done | sort -u
  )"

  if [ -n "$held_packages" ]; then
    echo "$held_packages" | xargs apt-mark hold
  fi
}

apt-get update
apt-get install -y openscan3-camera-stack
hold_installed_camera_packages

echo "dtoverlay=arducam-64mp" >> /boot/firmware/config.txt
echo "dtoverlay=vc4-kms-v3d,cma-512" >> /boot/firmware/config.txt
EOF
