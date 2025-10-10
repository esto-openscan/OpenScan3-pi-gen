#!/bin/bash -e

on_chroot << 'EOF'
set -e

echo "Generic camera selected — using stock libcamera packages."
echo "# generic cam – no dtoverlay" >> /boot/firmware/config.txt
EOF
