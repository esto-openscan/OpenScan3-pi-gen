#!/bin/bash -e

on_chroot << 'EOF'
set -e

echo "Installing OpenScan Hawkeye camera stack..."

apt-get update
apt-get install -y openscan3-hawkeye-camera-stack

audit_output="$(dpkg --audit)"
if [ -n "$audit_output" ]; then
  printf '%s\n' "$audit_output" >&2
  exit 1
fi

held_packages="$(
  dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' \
    'libcamera*' 'rpicam*' 'librpicam*' python3-libcamera python3-picamera2 \
    'python3-kms++' 'arducam*' 'pivariety*' 2>/dev/null \
    | awk '$1 == "ii" { print $2 }' | sort -u
)"
test -n "$held_packages"
printf '%s\n' "$held_packages" | xargs apt-mark hold
actual_holds="$(apt-mark showhold)"
for package in $held_packages; do
  printf '%s\n' "$actual_holds" | grep -Fxq "$package"
done

dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package} ${Version}\n' \
  openscan3-hawkeye-camera-stack \
  libcamera0.7 \
  libcamera-dev \
  libcamera-ipa \
  rpicam-apps \
  rpicam-apps-core \
  rpicam-apps-preview \
  rpicam-apps-encoder \
  rpicam-apps-opencv-postprocess \
  librpicam-app1 \
  librpicam-app-dev \
  python3-libcamera \
  python3-picamera2 \
  python3-kms++ \
  rpicam-apps-lite | awk '{ print } $1 != "ii" && $1 != "hi" { failed=1 } END { exit failed }'

grep -q '^# package: openscan3-hawkeye-camera-stack$' /boot/firmware/config.txt
grep -q '^dtoverlay=arducam-64mp$' /boot/firmware/config.txt
grep -q '^dtoverlay=vc4-kms-v3d,cma-512$' /boot/firmware/config.txt
EOF
