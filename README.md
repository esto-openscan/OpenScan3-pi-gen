# OpenScan3 Pi Image Builder

This repository wraps [Raspberry Pi OS pi-gen](https://github.com/RPi-Distro/pi-gen) and [OpenScan3](https://github.com/OpenScan-org/OpenScan3)  as a submodules and adds custom stages for camera setups and a preliminary [Node-RED](https://nodered.org/) web frontend. It produces Raspberry Pi OS Lite based images with camera-specific tweaks and the OpenScan3 firmware.

This is a work in progress and should be considered experimental.

## Repository Layout

- `pi-gen/` &mdash; upstream pi-gen submodule. Do not modify directly; keep customizations outside.
- `OpenScan3/` &mdash; OpenScan3 application/firmware as a git submodule. Synced into `/opt/openscan3` during `stage3-openscan/00-base`.
- `stage3-openscan/` &mdash; additional OpenScan3 stages appended after the stock `stage0`&ndash;`stage2` pipeline.
- `camera-configs/` &mdash; per-camera environment files declaring `IMG_NAME`, `CAMERA_TYPE`, and the `STAGE_LIST` to build.
- `build-all.sh` &mdash; helper script that loads camera configs and invokes `pi-gen/build.sh`.

## Prerequisites

- Debian/Ubuntu host or a compatible container with the packages pi-gen expects (see pi-gen docs).
- Disk space: pi-gen requires several GB for work directories and resulting images.
- `sudo` optional. When available, the build script uses `sudo`; otherwise it runs commands directly.

## Initial Setup

```bash
# clone with submodules
git clone --recurse-submodules https://github.com/esto-openscan/OpenScan3-pi-gen.git
cd OpenScan3-pi-gen

# if already cloned without submodules
git submodule update --init --recursive

# if the OpenScan3 submodule is not yet added in your clone, add it once
git submodule add --name OpenScan3 https://github.com/esto-openscan/OpenScan3.git OpenScan3
# build a single variant by short name (maps to camera-configs/generic.env)
./build-all.sh generic

# build by providing explicit env file path
./build-all.sh camera-configs/imx519.env

# build multiple variants in sequence
./build-all.sh generic imx519

# build every available variant (default when no args given)
./build-all.sh
```

Environment variables inside each `.env` are exported before launching `pi-gen/build.sh`. Customize or add new configs by copying an existing file in `camera-configs/` and adjusting values.

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

1. Pull upstream `pi-gen` and `OpenScan3` updates:
   ```bash
   git submodule sync --recursive 
   git submodule update --remote --checkout --recursive # checkout instead of merging local branches 
   git add pi-gen OpenScan3 
   git commit -m "Update submodules (pi-gen@arm64, OpenScan3@feature/os3-package)" 
   ```
2. Rebuild target images.
3. Publish resulting `.img` files from `pi-gen/deploy/`.
