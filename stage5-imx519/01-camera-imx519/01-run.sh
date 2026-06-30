#!/bin/bash -e

on_chroot << 'EOF'
set -e
set -o pipefail

echo "Configuring Arducam IMX519 camera..."

hold_installed_camera_packages() {
  protected_patterns='libcamera* rpicam* librpicam* python3-libcamera python3-picamera2 python3-kms++ arducam* pivariety*'
  held_packages="$(
    for pattern in $protected_patterns; do
      dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' "$pattern" 2>/dev/null || true
    done | awk '$1 == "ii" { print $2 }' | sort -u
  )"

  if [ -n "$held_packages" ]; then
    echo "$held_packages" | xargs apt-mark hold
  fi
}

camera_stack_install_targets() {
  apt-cache show openscan3-arducam-camera-stack |
    awk '
      /^Depends: / {
        deps = substr($0, 10)
        gsub(/, /, "\n", deps)
        print deps
      }
    ' |
    sed -n 's/^\([^ ]*\) (= \([^)]*\))$/\1=\2/p'
}

apt-get update
mapfile -t camera_stack_targets < <(camera_stack_install_targets)

if [ "${#camera_stack_targets[@]}" -eq 0 ]; then
  echo "Failed to resolve openscan3-arducam-camera-stack dependency versions" >&2
  exit 1
fi

printf 'Installing OpenScan camera stack targets:\n'
printf '  %s\n' openscan3-arducam-camera-stack "${camera_stack_targets[@]}"

apt-get install -y --allow-downgrades --allow-change-held-packages \
  openscan3-arducam-camera-stack \
  "${camera_stack_targets[@]}"

dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package} ${Version}\n' \
  openscan3-arducam-camera-stack \
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
  rpicam-apps-lite | awk '{ print } $1 != "ii" { failed=1 } END { exit failed }'

hold_installed_camera_packages

echo "dtoverlay=imx519" >> /boot/firmware/config.txt
EOF
