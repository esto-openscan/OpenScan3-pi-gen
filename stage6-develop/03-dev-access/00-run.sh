#!/bin/bash -e

# Enable interactive SSH access for develop images and set a known password
# for the 'openscan' service account. These changes are intentionally
# restricted to stage6-develop builds.

on_chroot <<'EOF'
set -e

echo 'openscan:openscan' | chpasswd
systemctl enable ssh
install -d -o openscan -g openscan -m 0700 /home/openscan
usermod --home /home/openscan openscan
chsh -s /bin/bash openscan
adduser openscan sudo
install -d -o root -g root -m 0755 /etc/ssh/sshd_config.d
printf '%s\n' \
    'Match User openscan' \
    '    PasswordAuthentication yes' \
    'Match all' \
    > /etc/ssh/sshd_config.d/90-openscan-develop.conf
chmod 0644 /etc/ssh/sshd_config.d/90-openscan-develop.conf
install -d -o root -g root -m 0755 /run/sshd

getent passwd openscan | grep -q '^openscan:.*:/home/openscan:/bin/bash$'
test "$(stat -c '%U:%G:%a' /home/openscan)" = 'openscan:openscan:700'
id -nG openscan | grep -qw sudo
systemctl is-enabled ssh >/dev/null
sshd -t
sshd -T -C user=openscan,host=localhost,addr=127.0.0.1 \
  | grep -q '^passwordauthentication yes$'
EOF
