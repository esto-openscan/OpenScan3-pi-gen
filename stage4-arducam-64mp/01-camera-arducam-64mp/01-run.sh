#!/bin/bash -e

on_chroot << 'EOF'
set -e

echo "Configuring Arducam 64MP camera..."

install_pivariety_packages() {
  echo "Installing Arducam libcamera packages..."
  wget -O /tmp/install_pivariety_pkgs.sh \
    https://github.com/ArduCAM/Arducam-Pivariety-V4L2-Driver/releases/download/install_script/install_pivariety_pkgs.sh
  chmod +x /tmp/install_pivariety_pkgs.sh
  /tmp/install_pivariety_pkgs.sh -p libcamera_dev
  /tmp/install_pivariety_pkgs.sh -p libcamera_apps
}

install_pivariety_packages

echo "dtoverlay=arducam-64mp" >> /boot/firmware/config.txt
echo "dtoverlay=vc4-kms-v3d,cma-512" >> /boot/firmware/config.txt
EOF
