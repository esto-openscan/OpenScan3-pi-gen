#!/bin/bash -e

on_chroot <<'EOF'
python3 - <<'PY'
from pathlib import Path

conf_path = Path('/etc/samba/smb.conf')
lines = conf_path.read_text().splitlines()
header = '[openscan-projects]'
keys_to_strip = {'comment', 'read only', 'writeable', 'create mask', 'directory mask'}
inside = False
rewritten = []

rw_block = [
    '   comment = OpenScan3 Projects (read/write dev override)',
    '   path = /var/openscan3/projects',
    '   browseable = yes',
    '   guest ok = yes',
    '   read only = no',
    '   writeable = yes',
    '   force user = openscan',
    '   force group = openscan',
    '   create mask = 0664',
    '   directory mask = 2775',
]

for line in lines:
    stripped = line.strip()
    if stripped.startswith('['):
        if inside:
            rewritten.extend(rw_block)
            inside = False
        rewritten.append(line)
        if stripped == header:
            inside = True
        continue

    if inside:
        key = stripped.split('=', 1)[0].strip() if '=' in stripped else stripped
        if key in keys_to_strip or stripped == '':
            continue

    rewritten.append(line)

if inside:
    rewritten.extend(rw_block)

conf_path.write_text('\n'.join(rewritten) + '\n')
PY

systemctl restart smbd nmbd || true
EOF
