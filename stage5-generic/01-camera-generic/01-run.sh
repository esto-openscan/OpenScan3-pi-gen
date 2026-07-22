#!/bin/bash -e

on_chroot << 'EOF'
set -e

echo "Installing OpenScan generic camera stack..."

audit_output="$(dpkg --audit)"
if [ -n "$audit_output" ]; then
  printf '%s\n' "$audit_output" >&2
  exit 1
fi

held_packages="$(
  dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
    'libcamera*' 'rpicam*' 'librpicam*' python3-libcamera python3-picamera2 \
    'python3-kms++' 'arducam*' 'pivariety*' 2>/dev/null \
    | awk '$1 == "ii" { print $2 }' | sort -u
)"
test -n "$held_packages"
printf '%s\n' "$held_packages" | xargs apt-mark hold
actual_holds="$(apt-mark showhold)"
for package in $held_packages; do
  if ! printf '%s\n' "$actual_holds" | grep -Fxq "$package"; then
    echo "Expected camera package to be held: $package" >&2
    exit 1
  fi
done

dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' \
  openscan3-generic-camera-stack \
  python3-libcamera \
  python3-picamera2 \
  rpicam-apps-lite | awk '{ print } $1 != "ii" && $1 != "hi" { failed=1 } END { exit failed }'

if grep -q '^# BEGIN OPENSCAN CAMERA STACK$' /boot/firmware/config.txt; then
  echo "Generic camera stack must not install a boot overlay." >&2
  exit 1
fi
EOF
