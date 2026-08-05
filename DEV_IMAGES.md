# OpenScan3 Develop Images

Develop images are built by adding `stage6-develop` with
`./build-all.sh --with-develop <variant>` or
`./build-all-docker.sh --with-develop <variant>`. They boot the signed,
APT-installed OpenScan runtime from the `nightly` suite and add tools for
testing a firmware checkout on the device. None of these additions belong in a
production image.

> Security warning: a Develop image enables SSH, gives the internal
> `openscan` account the known password `openscan` and membership in `sudo`,
> enables password authentication for that account, and exposes writable guest
> Samba shares. Task autodiscovery also permits test tasks to replace built-in
> task names. Use these images only on a trusted, isolated network; never ship
> or deploy one as a production scanner image.

## Added stages

| Stage | Effect |
| --- | --- |
| `00-channel-nightly` | Replaces the package source with the signed `nightly` suite and validates it with `openscan-updater channel --json`. |
| `00-samba-dev` | Adds development, community-task, and read-only log shares. |
| `01-openscan-service` | Adds task-autodiscovery environment variables through a systemd drop-in. |
| `02-samba-overrides` | Makes the normal projects share writable for Develop images. |
| `03-dev-access` | Enables SSH and configures the `openscan` service account for interactive development access. |
| `04-openscan-dev-deploy` | Installs the `openscan-dev` checkout/deployment helper. |

## Samba shares

All images provide the guest-readable `[openscan-projects]` share at
`/var/openscan3/projects`. In Develop images, that share is rewritten to be
writable. The following additional shares are appended:

| Share | Path | Access |
| --- | --- | --- |
| `[openscan-community-tasks]` | `/var/openscan3/community-tasks` | guest read/write |
| `[openscan-dev]` | `/opt/openscan3-dev` | guest read/write |
| `[openscan-logs]` | `/var/log/openscan3` | guest read-only |

Writable shares force the `openscan` user and group and use `0664` file and
`2775` directory masks. The log share is read-only, even though it also forces
the OpenScan account for Samba access.

## Firmware checkout workflow

`openscan-dev` leaves the package-owned runtime intact until you explicitly
deploy a checkout. It clones or updates its configured Git repository at
`/opt/openscan3-dev/src`, creates `/opt/openscan3-dev/venv`, and writes the
following service override:

```text
/etc/systemd/system/openscan3.service.d/20-dev-override.conf
```

The override runs the firmware from that checkout. Return to the packaged
runtime at any time with `sudo openscan-dev disable`.

```bash
# Inspect configured source and override state
openscan-dev status

# Deploy the default OpenScan firmware branch
sudo openscan-dev deploy

# Deploy a fork or a branch
sudo openscan-dev deploy \
  --repo https://github.com/your-user/OpenScan3.git \
  --branch feature/my-change

# Use the existing checkout again, or disable it
sudo openscan-dev enable
sudo openscan-dev disable
```

## Task discovery

`stage6-develop/01-openscan-service` writes
`/etc/systemd/system/openscan3.service.d/10-dev-task-flags.conf`:

```ini
[Service]
Environment="OPENSCAN_TASK_AUTODISCOVERY=1"
Environment="OPENSCAN_TASK_OVERRIDE_ON_CONFLICT=1"
```

This is intentional only for development. It makes externally supplied task
definitions discoverable and allows a discovered task to replace an existing
name.

## Relevant ownership boundaries

The base `openscan3.service`, nginx configuration, updater, and runtime files
are owned by Debian packages installed in `stage3-openscan`; they are not copied
from a pi-gen service-unit directory. The Develop stages add only drop-ins,
Samba/SSH configuration, and the `openscan-dev` helper around that package-owned
baseline.
