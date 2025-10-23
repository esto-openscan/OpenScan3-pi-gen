#!/bin/bash -e

on_chroot << 'EOF'
set -e

echo "Configuring Arducam IMX519 camera..."

install_pivariety_packages() {
  echo "Installing Arducam libcamera packages..."
  wget -O /tmp/install_pivariety_pkgs.sh \
    https://github.com/ArduCAM/Arducam-Pivariety-V4L2-Driver/releases/download/install_script/install_pivariety_pkgs.sh
  chmod +x /tmp/install_pivariety_pkgs.sh
  /tmp/install_pivariety_pkgs.sh -p libcamera_dev
  /tmp/install_pivariety_pkgs.sh -p libcamera_apps
}

install_pivariety_packages

echo "dtoverlay=imx519" >> /boot/firmware/config.txt
EOF
