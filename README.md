# OpenScan3 Pi Image Builder

This repository wraps [Raspberry Pi OS pi-gen](https://github.com/RPi-Distro/pi-gen) as a submodule and adds custom stages for camera setups. It produces Raspberry Pi OS Lite based images with camera-specific tweaks and the package-based OpenScan3 runtime from the signed OpenScan APT repository.

For instructions on using the generated images, see the [image documentation](DOCUMENTATION.md).

## Repository Layout

- `pi-gen/` &mdash; upstream pi-gen submodule. Do not modify directly; keep customizations outside.
- `stage3-openscan/` &mdash; additional OpenScan3 stages appended after the stock `stage0`&ndash;`stage2` pipeline. This is the package-based runtime baseline.
- `stage6-develop/` &mdash; optional develop-image stage with SSH/dev access, Samba dev shares, task autodiscovery flags, and `openscan-dev` for Git-based firmware testing on-device.
- `stage4-nodered/` &mdash; unused legacy stage for the deprecated Node-RED frontend.
- `stage5-[camera-config]` &mdash; camera-specific stages appended after the stock `stage3` pipeline.
- `build-configs/` &mdash; shared and per-camera environment files declaring `CAMERA_TYPE`, image suffixes, and the `STAGE_LIST` to build. The image version prefix is resolved from the `openscan3-firmware` Debian package in the signed OpenScan APT repository.
- `build-all.sh` &mdash; helper script that loads camera configs and invokes `pi-gen/build.sh`.

## Prerequisites

- Debian/Ubuntu host or a compatible container with the packages pi-gen expects (see pi-gen docs).
- Disk space: pi-gen requires several GB for work directories and resulting images.
- `sudo` optional. When available, the build script uses `sudo`; otherwise it runs commands directly.

## Initial Setup

```bash
# clone with submodules
git clone --recurse-submodules https://github.com/OpenScan-org/OpenScan3-pi-gen.git
cd OpenScan3-pi-gen

# if already cloned without submodules
git submodule update --init --recursive

# prepare local sources (sync pi-gen submodule)
./scripts/prepare-build.sh

# build a single variant by short name (maps to build-configs/generic.env)
./build-all.sh generic

# build by providing explicit env file path
./build-all.sh build-configs/imx519.env

# build multiple variants in sequence
./build-all.sh generic imx519

# build every available variant (default when no args given)
./build-all.sh

# or build via docker (runs inside container; still fine to call prepare-build first)
./build-all-docker.sh generic imx519
```

Environment variables inside each `.env` are exported before launching `pi-gen/build.sh`. Customize or add new configs by copying an existing file in `build-configs/` and adjusting values. The Docker helper `build-all-docker.sh` generates a temporary config per camera and calls `pi-gen/build-docker.sh -c …`; deployment artifacts still land under `pi-gen/deploy/`.

## Customizing Stages

1. Add new stage directories inside `stage3-openscan/` following the pi-gen stage layout (`00-config`, `01-run.sh`, etc.).
2. Reference those stages in the desired `STAGE_LIST` within a camera config.
3. Keep upstream `pi-gen` untouched; commit your changes outside the submodule.

## Cleaning Up

Builds create work under `pi-gen/work/` and images under `pi-gen/deploy/`.

```bash
rm -rf pi-gen/work pi-gen/deploy
```

## Releasing Updates

1. Pull upstream `pi-gen` updates:
   ```bash
   git submodule sync pi-gen
   git submodule update --remote --checkout pi-gen
   git add pi-gen
   git commit -m "Update pi-gen submodule"
   ```
2. Rebuild target images.
3. Publish resulting `.img` files from `pi-gen/deploy/`.

## Build Script Reference

### `build-all.sh`

CLI wrapper for native builds (runs `pi-gen/build.sh`):

- `./build-all.sh` &mdash; build every camera config under `build-configs/` (excluding `base.env`).
- `./build-all.sh generic` &mdash; build a single config without Arducam drivers (looks for `build-configs/generic.env`).
- `./build-all.sh build-configs/imx519.env` &mdash; build via explicit path.
- `./build-all.sh --skip-cleanup …` &mdash; skip the interactive cache cleanup prompt.
- `./build-all.sh --with-develop ...` &mdash; append `stage6-develop` after the selected `STAGE_LIST` to add SSH/dev access, Samba dev shares, and the `openscan-dev` Git deploy helper.
- Run `./scripts/prepare-build.sh` beforehand when building outside Docker to ensure the `pi-gen` submodule is present. Firmware defaults and client assets are installed by Debian packages from the signed OpenScan APT repository.

Environment loading is handled by `scripts/config-loader.sh`. Each run exports the common defaults from `build-configs/base.env`, resolves the image version from the `openscan3-firmware` APT package, then overlays the selected camera `.env`. The script auto-detects `sudo`; on systems without `sudo` it runs pi-gen directly.

### `build-all-docker.sh`

Containerized variant that invokes `pi-gen/build-docker.sh -c <temp-config>` per camera:

- Accepts the same positional arguments and flags as `build-all.sh` (`--skip-cleanup`, `--with-develop`, `.env` paths or short names).
- Creates a temporary, per-camera config file with the resolved `STAGE_LIST`, `IMG_NAME`, and `TARGET_HOSTNAME`.
- Exposes work/deploy/cache directories via bind mounts (`$PI_GEN_DIR/work`, `$PI_GEN_DIR/deploy`, `.cache/pi-gen/apt`) so artifacts persist on the host.

Both scripts respect the `STAGE_LIST` declared in each camera env. By default builds stop after `stage3-openscan`; pass `--with-develop` to append `stage6-develop`. Use the legacy Stage 4 only by manually editing `STAGE_LIST` if Node-RED testing is required.

## Develop Images

Develop images boot from the signed APT-installed OpenScan runtime on the `nightly` channel by default. Normal images use the `stable` channel. To test firmware from a Git repository on the Pi, use the `openscan-dev` helper installed by `stage6-develop`:

```bash
sudo openscan-dev deploy --repo https://github.com/OpenScan-org/OpenScan3.git --branch develop
sudo openscan-dev deploy --repo https://github.com/your-user/OpenScan3.git --branch feature/my-change
openscan-dev status
```

`openscan-dev deploy` clones or updates `/opt/openscan3-dev/src`, rebuilds `/opt/openscan3-dev/venv`, and installs a systemd drop-in that points `openscan3.service` at that checkout. Return to the package-owned runtime with:

```bash
sudo openscan-dev disable
```
