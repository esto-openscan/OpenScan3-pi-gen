# OpenScan3 Develop Images

This document summarizes the additional steps that are applied when building the
`stage6-develop` image variant. These changes support local firmware
development, rapid iteration, and debugging, and they do **not** ship in regular
production images.

> **Security warning:** develop images deliberately expose writable Samba
> shares, task overrides, and other debug conveniences. Treat them as
> inherently unsafe and operate only inside isolated, trusted subnets without
> external access.

## Stage overview

| Stage | Purpose |
|-------|---------|
| `stage6-develop/00-samba-dev` | Adds extra Samba exports for development assets and data. |
| `stage6-develop/01-openscan-service` | Injects dev-specific environment variables into the `openscan3` systemd unit via a drop-in. |

## Samba additions

File: `stage6-develop/00-samba-dev/00-run.sh`

The following writable shares are appended to `/etc/samba/smb.conf` inside the
image:

- **`[openscan3-client]`** → `/opt/openscan3-client`
  - Allows editing the SPA bundle over the network.
- **`[openscan-community-tasks]`** → `/var/openscan3/community-tasks`
  - Mirrors the persistent community task directory for quick sync.
- **`[openscan-dev]`** → `/opt/openscan3`
  - Exposes the firmware checkout so developers can push/pull changes remotely.

All three shares inherit `force user/group = openscan` and `0664/2775` masks so
files created from a Samba client have the expected permissions.

## Task discovery flags

File: `stage6-develop/01-openscan-service/00-run.sh`

This stage writes `/etc/systemd/system/openscan3.service.d/10-dev-task-flags.conf`
with the following environment overrides:

```ini
[Service]
Environment="OPENSCAN_TASK_AUTODISCOVERY=1"
Environment="OPENSCAN_TASK_OVERRIDE_ON_CONFLICT=1"
```

Using a systemd drop-in keeps the base unit (`stage3-openscan/00-base/.../openscan3.service`)
untouched. These variables enable automatic registration of tasks and allow
community tasks to override built-in task names when necessary, which is helpful
for experimental development.

## Lifecycle notes

- The drop-in and extra Samba shares exist **only** in images that include
  `stage6-develop` in their `STAGE_LIST`.
- Production images continue to use the base paths (`/var/openscan3/projects`
  share only) and default task discovery settings.

## Related files

- `stage3-openscan/01-samba/files/etc/samba/smb.conf` – base Samba config used in all builds.
- `stage3-openscan/00-base/files/etc/systemd/system/openscan3.service` – base service unit before drop-ins.
- `stage6-develop/prerun.sh` – ensures the previous stage artifacts are copied before applying develop tweaks.
