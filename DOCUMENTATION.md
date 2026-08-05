# OpenScan3 Pi Image – User Guide

This guide explains how to use the Raspberry Pi image produced by this repository. The image is based on Raspberry Pi OS Lite and ships with OpenScan3-Firmware (FastAPI backend) plus the Vue.js/Quasar-based OpenScan3-Client SPA, alongside camera-specific tweaks depending on the chosen build variant.

## TL;DR

- Flash the image using Raspberry Pi Imager and, in Advanced options, set the hostname, create a user (do NOT name it `openscan`), and configure Wi‑Fi.
- Optionally enable SSH in Raspberry Pi Imager for headless access.
- Boot the Pi, connect it to your network (Ethernet recommended for first boot).
- Open a browser to `http://openscan/` or the Pi’s IP.
- You’ll land on the OpenScan3-Client dashboard (served at `/`).
- API is available on the device at `http://<pi>/api/` (proxied by nginx) and directly at `http://<pi>:8000/latest`.
- API documentation is available at `http://<pi>/api/latest/docs`.
---

## What’s in the image

- **OpenScan3 service**
  - Installed from the signed OpenScan APT repository as `openscan3-firmware`.
  - Runtime releases live under `/opt/openscan3/releases/`, with `/opt/openscan3/current` pointing at the active release.
  - Systemd unit: `openscan3.service` (owned by the Debian package).

- **OpenScan3-Client web UI**
  - Installed from the signed OpenScan APT repository as `openscan3-client`.
  - Vue.js/Quasar SPA files are in `/usr/share/openscan3-client`.
  - Served statically by nginx (no separate systemd service).
  - Default routes: `/` (dashboard) with history fallback handled by nginx.

- **nginx reverse proxy**
  - Installed and configured by `openscan3-system-config`.
  - Package-owned site `/etc/nginx/sites-available/openscan3.conf` proxies `/api` to the OpenScan3 FastAPI backend (`127.0.0.1:8000`) and serves the SPA from `/usr/share/openscan3-client`.
  - It also exposes the independent updater recovery UI at `/recovery/` and
    redirects the legacy `/admin` path there.

- **OpenScan3 system configuration**
  - Installed from the signed OpenScan APT repository as `openscan3-system-config`.
  - Owns the nginx site, OpenScan APT public key and source file, update policy defaults, updater sudoers bridge, tmpfiles directories, and logrotate defaults.
  - Replaces the old pi-gen-owned nginx/admin glue. The legacy PHP updater is
    not part of the image; `/admin` is retained only as a redirect to
    `/recovery/`.

- **Persistent settings**
  - OpenScan settings are stored in `/etc/openscan3` (created and made group-writable by `stage3-openscan/00-base/01-run.sh`).

- **Updater**
  - Installed from the signed OpenScan APT repository as `openscan3-updater`.
  - CLI entry point: `openscan-updater`.
  - The firmware backend can call narrow updater commands through `/etc/sudoers.d/openscan-updater`.

- **Develop image helper** (`--with-develop` builds only)
  - CLI entry point: `openscan-dev`.
  - Lets developers deploy and test OpenScan3 firmware from a configurable Git repository and branch.
  - Uses `/opt/openscan3-dev` and a systemd drop-in instead of changing the package-owned runtime files.

## Supported variants (camera-specific)

Select the right image for your camera. Differences are applied in stage 5.

- **Generic (experimental)** (`stage5-generic`)
  - Installs `openscan3-generic-camera-stack`.
  - No camera overlay is forced.

- **IMX519** (`stage5-imx519`)
  - Installs `openscan3-imx519-camera-stack`.
  - The package writes an OpenScan-managed `dtoverlay=imx519` block to `/boot/firmware/config.txt`.

- **Arducam 64MP (HawkEye) ** (`stage5-arducam-64mp`)
  - Installs `openscan3-hawkeye-camera-stack`.
  - The package writes an OpenScan-managed block to `/boot/firmware/config.txt`:
    - `dtoverlay=arducam-64mp`
    - `dtoverlay=vc4-kms-v3d,cma-512` (increases CMA for high-res camera)
  - Camera stack packages conflict with each other to avoid mixing hardware profiles.

Official pi-gen images include `/etc/openscan3/image-build.json` for support
triage. If that file is missing, the installation did not come from the
OpenScan pi-gen image build pipeline.

Your build variant is chosen via the `.env` config used at build time (see
`build-configs/*.env`).

## First boot and network access

- **User account (important)**: Use the user you created in Raspberry Pi Imager. Do not create a user named `openscan` — this name is reserved for the internal service account created by the image. If you did not create a user while flashing, provision one from the SD card as described below before attempting to connect over SSH.
- **Network**:
  - If Wi‑Fi was configured in Raspberry Pi Imager, the Pi will join that network on first boot. If no network is configured, the device will automatically try to connect to a Wi-Fi from a qr code you can generate with your smartphone.
- **Hostname**: Use the hostname you set in Raspberry Pi Imager. If not set, it defaults to `openscan3-alpha`.
- **Discovery**:
  - Default hostname is `http://openscan/` and via mDNS it resolves as `http://openscan.local/`.
  - Avahi publishes `_http._tcp` and `_smb._tcp` DNS‑SD records automatically, so Windows/macOS/Linux network browsers show an “OpenScan3” web endpoint and Samba share without extra setup. Changing the hostname (e.g., in Raspberry Pi Imager) propagates to these announcements on next boot.

### Provisioning SSH access after flashing

If an image was flashed without creating a user, use Raspberry Pi OS's standard
manual headless setup. The authoritative instructions are in the official
[Raspberry Pi documentation: Manual setup for SSH](https://www.raspberrypi.com/documentation/computers/getting-started.html#manual-setup-for-ssh).
The summary below only records the OpenScan-specific details.

This recovery procedure also works after an unprovisioned OpenScan image has
already been booted, provided that its initial user setup has never completed
successfully:

1. Shut down the scanner, remove the SD card, and insert it into another
   computer.
2. Open the FAT partition named `bootfs`.
3. Create an empty file named `ssh` in the root of that partition.
4. Generate a SHA-512 password hash as described by Raspberry Pi:

   ```bash
   openssl passwd -6
   ```

5. Create `userconf.txt` in the root of `bootfs` with exactly one line:

   ```text
   <username>:<encrypted-password>
   ```

6. Reinsert the SD card and boot the scanner. Raspberry Pi OS consumes both
   files, provisions the user, and enables SSH.
7. Connect with the provisioned username, for example:

   ```bash
   ssh <username>@openscan.local
   ```

Do not use `openscan` as the username; it is reserved for the internal service
account. For compatibility with the `userconf-pi` version shipped in the
current Trixie images, use a username beginning with a lowercase letter and
containing only lowercase letters, digits, and hyphens. After logging in,
configure SSH public-key authentication and disable password authentication
if the device will be accessible from an untrusted network.

`userconf.txt` is an initial-user provisioning mechanism, not a general user
manager. After initial user setup has completed successfully, Raspberry Pi OS
disables the corresponding setup service. Add further users from an existing
administrator account using the standard Raspberry Pi OS tools.

## Accessing the web UI

- Open `http://<pi>/` → serves the OpenScan3-Client SPA directly.
  - History mode fallback keeps URLs such as `/projects` working without manual nginx tweaks.
- FastAPI generated OpenAPI docs: `http://<pi>/api/latest/docs`
- OpenAPI JSON: `http://<pi>/api/latest/openapi.json`
- Typical endpoints consumed by the SPA: `/latest/device/info`, `/latest/projects`, and other REST/WS routes exposed by the firmware.
- Recovery UI: `http://<pi>/recovery/` (also reached through `/admin`). It is
  served by `openscan-updaterd`, so it remains available while the firmware
  service is restarted during an update.

## Services and logs

Run these on the Pi (SSH or local):

- **Status**
  - `systemctl status openscan3`
  - `systemctl status nginx`
  - `systemctl status openscan-updaterd`

- **Start/Stop/Restart**
  - `sudo systemctl restart openscan3`
  - `sudo systemctl restart nginx`

- **Logs**
  - `journalctl -u openscan3 -e -f`
  - `journalctl -u nginx -e -f`
  - `journalctl -u openscan-updaterd -e -f`

## File and directory layout (key locations)

- OpenScan app runtime: `/opt/openscan3/current`
- OpenScan release directories: `/opt/openscan3/releases/`
- Python venv for the service: `/opt/openscan3/current/venv`
- OpenScan3-Client static files: `/usr/share/openscan3-client`
- Nginx site config: `/etc/nginx/sites-available/openscan3.conf`
- OpenScan updater CLI: `/usr/bin/openscan-updater`
- OpenScan stable APT keyring: `/usr/share/keyrings/openscan-stable-archive-keyring.gpg`
- OpenScan nightly APT keyring: `/usr/share/keyrings/openscan-nightly-archive-keyring.gpg`
- OpenScan APT source: `/etc/apt/sources.list.d/openscan.sources`
- OpenScan update policy defaults: `/etc/openscan3/update-policy.json`
- OpenScan settings: `/etc/openscan3` (group-writable for `openscan`)
- Boot config: `/boot/firmware/config.txt` (camera overlays added per variant)
- Develop checkout root, if enabled: `/opt/openscan3-dev`
- Develop helper config, if enabled: `/etc/openscan3-dev/config.env`
- Develop service override, if enabled: `/etc/systemd/system/openscan3.service.d/20-dev-override.conf`

## Updating OpenScan3

OpenScan runtime updates are package-based. Normal images install the `stable` APT channel from `https://firmware.openscan.eu/apt`; develop images install the `nightly` channel. Switching channels changes future update candidates only and does not downgrade already installed packages.

Use the package-owned CLI to inspect the installed state or run the fixed
OpenScan update preflight:

```bash
openscan-updater status --json
openscan-updater update --dry-run --json
```

For appliance recovery, use `http://<pi>/recovery/` or the corresponding
`sudo openscan-updater repair --json` command. Do not use generic APT commands
to switch camera-stack providers.

## Develop Image Git Workflow

This section applies only to images built with `./build-all.sh --with-develop ...` or `./build-all-docker.sh --with-develop ...`.

Develop images include `openscan-dev`, which lets you test a firmware checkout without rebuilding the whole image. The image still starts with the signed APT-installed runtime until you explicitly deploy a checkout.

```bash
# Show current dev configuration and whether the systemd override is active
openscan-dev status

# Deploy the default configured repo/branch
sudo openscan-dev deploy

# Deploy a specific fork and branch
sudo openscan-dev deploy \
  --repo https://github.com/your-user/OpenScan3.git \
  --branch feature/my-change
```

The helper clones or updates `/opt/openscan3-dev/src`, rebuilds `/opt/openscan3-dev/venv`, writes `/etc/systemd/system/openscan3.service.d/20-dev-override.conf`, and restarts `openscan3.service`.

You can persist defaults without deploying immediately:

```bash
sudo openscan-dev config \
  --repo https://github.com/your-user/OpenScan3.git \
  --branch feature/my-change
```

Return to the package-owned runtime:

```bash
sudo openscan-dev disable
```

Re-enable an already prepared checkout:

```bash
sudo openscan-dev enable
```

The legacy PHP updater is not used for this workflow. Git repo URL and branch
are configured through `openscan-dev` and `/etc/openscan3-dev/config.env`.

## Flashing the image

- **Locate the image**: The build wrappers export release artifacts to
  `deploy/` (`.img`, `.img.xz`, or `.zip`). Raw pi-gen output remains in
  `pi-gen/deploy/`.

### Optional: generate a Raspberry Pi Imager manifest (online + local)

We ship `scripts/generate-imager-json.py` to emit both the hosted repository metadata (`imager/repo.json`) _and_ a manifest that points at your locally downloaded artifacts so the customization wizard stays enabled even when you select "Use custom".

1. Build or download your OpenScan images so they exist in `deploy/`.
2. Generate the manifests:

   ```bash
   ./scripts/generate-imager-json.py \
     --deploy-dir deploy \
     --local-manifest
   ```

   - `imager/repo.json`: reference file for publishing/hosting (HTTP URLs).
   - `imager/os_list_local.rpi-imager-manifest`: uses `file://` paths that Raspberry Pi Imager can open directly.

3. Launch Raspberry Pi Imager and either double-click the `.rpi-imager-manifest` file or go to **App Options → Content Repository → Use custom file** and select it. The **OS** list now shows your OpenScan builds with all customization sliders, including USB Gadget mode.

### Recommended: Raspberry Pi Imager with custom repository

> **Note:** Advanced customization (hostname, user, Wi‑Fi, etc.) is confirmed to work with Raspberry Pi Imager > 2.0.
> Older versions may not apply the customizations properly.

1. Open Raspberry Pi Imager (>=2.0.6).
2. Click **ADD OPTIONS** -> Click **EDIT** Content Repository -> Use custom URL and paste `https://openscan.eu/rpi-repo.json` -> Click **Apply and restart**
3. Choose your raspberry pi device
4. Select the image according to your camera variant. **IMPORTANT**: Ensure the image matches your camera model. Choosing the wrong image may result in permanent hardware damage. 
5. Select the storage device to write the image to.
6. Modify configuration options if needed (hostname, user, Wi‑Fi, etc.) via the Raspberry Pi Imager interface.
7. Write the image. Eject the card and insert it into the Pi.


## Troubleshooting

- **No dashboard on port 80**
  - Check services: `systemctl status nginx`.
  - Confirm `/usr/share/openscan3-client` contains the SPA (index.html, assets) and that `/etc/nginx/sites-available/openscan3.conf` exists.

- **UI shows setup screen / device not initialized**
  - Check OpenScan3: `systemctl status openscan3` and `journalctl -u openscan3 -e -f`.

- **Camera not detected / errors with libcamera** 
  - Verify the correct `openscan3-*-camera-stack` package is installed.
  - Verify `/boot/firmware/config.txt` contains the correct OpenScan-managed `dtoverlay` block for your variant.
  - For 64MP builds ensure the CMA overlay line exists: `dtoverlay=vc4-kms-v3d,cma-512`.
  - Power-cycle after changing overlays.

- **SPA caching issues after update**
  - Force-refresh the browser (Ctrl+Shift+R) or clear cache; nginx sets `no-store` headers but some proxies may still cache aggressively.

## Notes for advanced users

- The upstream pi-gen defaults include cloud-init support (see `pi-gen/README.md`). If your build used `ENABLE_CLOUD_INIT=1`, cloud-init will apply any config placed on the boot partition at first boot.
- Stage order per image is controlled by the `.env` you chose (see
  `build-configs/*.env`, variable `STAGE_LIST`).
