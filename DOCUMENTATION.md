# OpenScan3 Pi Image – User Guide

This guide explains how to use the Raspberry Pi image produced by this repository. The image is based on Raspberry Pi OS Lite and ships with OpenScan3 (FastAPI backend) and a Node-RED-based web UI, plus camera-specific tweaks depending on the chosen build variant.

## TL;DR

- Flash the image using Raspberry Pi Imager and, in Advanced options, set the hostname, create a user (do NOT name it `openscan`), and configure Wi‑Fi.
- Optionally enable SSH in Raspberry Pi Imager for headless access.
- Boot the Pi, connect it to your network (Ethernet recommended for first boot).
- Open a browser to `http://openscan3-alpha/` or the Pi’s IP.
- You’ll land on the OpenScan dashboard at `/dashboard`.
- API is available on the device at `http://<pi>:8000/latest`.
- API documentation is available at `http://<pi>:8000/latest/docs`.
---

## What’s in the image

- **OpenScan3 service**
  - Installed to `/opt/openscan3` and run in a Python venv.
  - Systemd unit: `openscan3.service` (see `stage3-openscan/00-base/files/etc/systemd/system/openscan3.service`).
  - Default API base used by the UI: `http://localhost:8000`

- **Node-RED web UI**
  - Runs as systemd service `node-red-openscan.service` (see `stage4-nodered/01-nodered/files/etc/systemd/system/node-red-openscan.service`).
  - User directory: `/opt/openscan3/node-red` with `flows.json` and `settings.js`.
  - Editor is enabled at `/nodered` and dashboard at `/dashboard`

- **nginx reverse proxy**
  - Listens on port 80 and proxies all paths to Node-RED on `127.0.0.1:1880`.
  - Root `/` redirects to `/dashboard/` (see `stage4-nodered/01-nodered/files/etc/nginx/sites-available/default`).

- **Persistent settings**
  - OpenScan settings are stored in `/etc/openscan3` (created and made group-writable by `stage3-openscan/00-base/01-run.sh`).

- **Updater**
  - A simple Updater for OpenScan3 and the Node-RED flows is reachable at `/admin`

## Supported variants (camera-specific)

Select the right image for your camera. Differences are applied in stage 5.

- **Generic (experimental)** (`stage5-generic`)
  - Installs stock `libcamera` packages.
  - Adds a comment to `/boot/firmware/config.txt`; no camera overlay is forced (see `stage5-generic/01-camera-generic/00-packages`, `01-run.sh`).

- **IMX519** (`stage5-imx519`)
  - Installs Arducam PiVariety `libcamera` packages.
  - Appends `dtoverlay=imx519` to `/boot/firmware/config.txt` (see `stage5-imx519/01-camera-imx519/01-run.sh`).

- **Arducam 64MP (HawkEye) (experimental)** (`stage5-arducam-64mp`)
  - Installs Arducam PiVariety `libcamera` packages.
  - Appends to `/boot/firmware/config.txt`:
    - `dtoverlay=arducam-64mp`
    - `dtoverlay=vc4-kms-v3d,cma-512` (increases CMA for high-res camera)
  - See `stage5-arducam-64mp/01-camera-arducam-64mp/01-run.sh`.

Your build variant is chosen via the `.env` config used at build time (see `camera-configs/*.env`).

## First boot and network access

- **User account (important)**: Use the user you created in Raspberry Pi Imager. Do not create a user named `openscan` — this name is reserved for the internal service account created by the image.
- **Network**:
  - If Wi‑Fi was configured in Raspberry Pi Imager, the Pi will join that network on first boot.
- **Hostname**: Use the hostname you set in Raspberry Pi Imager. If not set, it defaults to `openscan3-alpha`.
- **Discovery**: Default hostname is `http://openscan3-alpha/` and in networks with mDNS enabled it will be discoverable as `http://openscan3-alpha.local/`.

## Accessing the web UI

- Open `http://<pi>/` → redirects to `/dashboard` (Node-RED Dashboard from `OpenScan3/flows/flows.json`).
  - Node-RED editor: `http://<pi>/nodered`.
    - Note: The editor has no password by default in this image. Consider adding credentials in `/opt/openscan3/.node-red/settings.js` and restarting the service.
- FastAPI generated OpenAPI docs: `http://<pi>:8000/latest/docs`
- OpenAPI JSON: `http://<pi>:8000/latest/openapi.json`
- Typical endpoints referenced by the UI: `/latest/device/info`, camera settings endpoints, etc. (see calls in `OpenScan3/flows/flows.json`).

## Updater (experimental)
- Admin page (experimental): `http://<pi>/admin/`
  - Minimal PHP page to:
    - Download OpenScan3 device settings as tar.gz (`/etc/openscan3`).
    - Download Node-RED `flows.json`.
    - Trigger a quick update (see below). Default branch is `develop`.
  - Security: No authentication by default. Use only on trusted networks.

## Services and logs

Run these on the Pi (SSH or local):

- **Status**
  - `systemctl status openscan3`
  - `systemctl status node-red-openscan`
  - `systemctl status nginx`

- **Start/Stop/Restart**
  - `sudo systemctl restart openscan3`
  - `sudo systemctl restart node-red-openscan`
  - `sudo systemctl restart nginx`

- **Logs**
  - `journalctl -u openscan3 -e -f`
  - `journalctl -u node-red -e -f` (SyslogIdentifier=`node-red`)
  - `journalctl -u nginx -e -f`

## File and directory layout (key locations)

- OpenScan app (runtime, editable install): `/opt/openscan3`
- OpenScan git source copy: `/opt/openscan3-src` (used for future updates/sync)
- Python venv for the service: `/opt/openscan3/venv`
- Node-RED userDir: `/opt/openscan3/.node-red` (contains `flows.json`, `settings.js`)
- OpenScan settings: `/etc/openscan3` (group-writable for `openscan`)
- Boot config: `/boot/firmware/config.txt` (camera overlays added per variant)

## Updating OpenScan3 (application code)

The service is installed in editable mode from `/opt/openscan3`, so changes there take effect after a restart.

Example (on the Pi):

```bash
# Optional: update the source mirror
sudo -u openscan bash -lc 'cd /opt/openscan3-src && git remote -v && git fetch --all && git checkout <desired-branch> && git pull'

# Sync updated source into the runtime tree (without .git)
sudo rsync -av --delete --exclude '.git' /opt/openscan3-src/ /opt/openscan3/

# Restart the service
sudo systemctl restart openscan3
```

### Updater (highly experimental)

- CLI:
  ```bash
  # Default branch is develop; add flags to keep current settings/flows if desired
  sudo /usr/local/sbin/openscan3-update --branch develop [--keep-settings] [--keep-flows]
  ```
  - Stops services, force-resets `/opt/openscan3-src` to `origin/<branch>`, syncs to `/opt/openscan3`, rebuilds venv, resets `/etc/openscan3` and `/opt/openscan3/.node-red/flows.json` (unless kept), restarts services.

- Web:
  - Open `http://<pi>/admin/` and use the form to trigger the same updater.
  - You can choose branch and optionally keep settings and/or flows.

To modify Node-RED flows, edit `/opt/openscan3/.node-red/flows.json` via the editor (`/nodered`) and deploy. The file persists across reboots.

## Flashing the image

- **Locate the image**: Find the generated image in `pi-gen/deploy/` (`.img`, `.img.xz`, or `.zip`).

### Recommended: Raspberry Pi Imager

1. Open Raspberry Pi Imager (v1.7+ recommended).
2. OS → Use custom → select your built image from `pi-gen/deploy/`.
3. Storage → select your microSD card.
4. Click the gear icon (Advanced options) and set:
   - Hostname (e.g., `openscan-beta.local`).
   - Username and password for your primary user. Do NOT use `openscan`.
   - Wi‑Fi SSID, password, and country.
   - Optional: enable SSH and set locale/timezone/keyboard.
5. Write the image. Eject the card and insert it into the Pi.

### Alternative: Other flashers (balenaEtcher)

- Flash the image normally, then configure hostname/user/Wi‑Fi after first boot via HDMI/keyboard and `raspi-config` (or with cloud-init files on the boot partition, see `pi-gen/README.md`).

## Troubleshooting

- **No dashboard on port 80**
  - Check services: `systemctl status nginx node-red-openscan`.
  - Confirm Node-RED is listening on `127.0.0.1:1880` and nginx config exists at `/etc/nginx/sites-available/default`.

- **UI shows setup screen / device not initialized**
  - Check OpenScan3: `systemctl status openscan3` and `journalctl -u openscan3 -e -f`.

- **Camera not detected / errors with libcamera**
  - Verify `/boot/firmware/config.txt` contains the correct `dtoverlay` for your variant.
  - For 64MP builds ensure the CMA overlay line exists: `dtoverlay=vc4-kms-v3d,cma-512`.
  - Power-cycle after changing overlays.

- **Editor security**
  - By default, the Node-RED editor (`/nodered`) is reachable via nginx. To restrict access, add credentials in `/opt/openscan3/.node-red/settings.js` and/or firewall the device.

## Notes for advanced users

- The upstream pi-gen defaults include cloud-init support (see `pi-gen/README.md`). If your build used `ENABLE_CLOUD_INIT=1`, cloud-init will apply any config placed on the boot partition at first boot.
- Stage order per image is controlled by the `.env` you chose (see `camera-configs/*.env`, variable `STAGE_LIST`).
