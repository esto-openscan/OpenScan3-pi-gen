# OpenScan3 Pi Image Builder

This repository wraps [Raspberry Pi OS pi-gen](https://github.com/RPi-Distro/pi-gen) as a submodule and adds custom stages for camera setups. It produces Raspberry Pi OS Lite based images with camera-specific tweaks and the package-based OpenScan3 runtime from the signed OpenScan APT repository.

For instructions on using the generated images, see the [image documentation](DOCUMENTATION.md).

## Release boundary

This repository builds images; it does not build the OpenScan runtime packages
from source. `stage3-openscan` installs firmware, client, updater, and system
configuration from the signed OpenScan APT repository. The package build host
therefore publishes the required APT suite first, and pi-gen consumes it when
building an image:

```text
package source -> build host -> signed OpenScan APT suite -> this image builder
```

Normal images consume `stable`. Adding `--with-develop` produces a Develop
image that consumes `nightly`. Build the image only after the intended suite is
published; its version prefix is taken from the current
`openscan3-firmware` candidate in that suite. Each completed build records its
inputs in `/etc/openscan3/image-build.json` for support triage.

## Repository Layout

- `pi-gen/` &mdash; upstream pi-gen submodule. Do not modify directly; keep customizations outside.
- `stage3-openscan/` &mdash; additional OpenScan3 stages appended after the stock `stage0`&ndash;`stage2` pipeline. This is the package-based runtime baseline.
- `stage6-develop/` &mdash; optional develop-image stage with SSH/dev access, Samba dev shares, task autodiscovery flags, and `openscan-dev` for Git-based firmware testing on-device.
- `stage4-nodered/` &mdash; unused legacy stage for the deprecated Node-RED frontend.
- `stage5-[camera-config]` &mdash; camera-specific stages appended after the stock `stage3` pipeline.
- `build-configs/` &mdash; shared and per-camera environment files declaring `CAMERA_TYPE`, image suffixes, and the `STAGE_LIST` to build. The image version prefix is resolved from the `openscan3-firmware` Debian package in the signed OpenScan APT repository.
- `build-all.sh` &mdash; helper script that loads camera configs and invokes `pi-gen/build.sh`.
- `deploy/` &mdash; sanitized release artifacts exported by the wrapper. Raw pi-gen output remains under `pi-gen/deploy/`.

## Prerequisites

- Debian/Ubuntu host or a compatible container with the packages pi-gen expects (see pi-gen docs).
- Disk space: pi-gen requires several GB for work directories and resulting images.
- `sudo` optional. When available, the build script uses `sudo`; otherwise it runs commands directly.
- Network access to the signed OpenScan APT suite to be installed (`stable` for normal images; `nightly` for Develop images).

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

# build only the nightly/develop IMX519 image
./build-all-docker.sh --develop-only imx519
```

Environment variables inside each `.env` are exported before launching `pi-gen/build.sh`. Customize or add new configs by copying an existing file in `build-configs/` and adjusting values. The Docker helper `build-all-docker.sh` generates a temporary config per camera and calls `pi-gen/build-docker.sh -c …`; raw artifacts land under `pi-gen/deploy/` and the wrapper exports release artifacts to `deploy/`.

## Customizing Stages

1. Add new stage directories inside `stage3-openscan/` following the pi-gen stage layout (`00-config`, `01-run.sh`, etc.).
2. Reference those stages in the desired `STAGE_LIST` within a camera config.
3. Keep upstream `pi-gen` untouched; commit your changes outside the submodule.

## Cleaning Up

Builds keep their working tree under `pi-gen/work/`, raw pi-gen artifacts under
`pi-gen/deploy/`, and exported release artifacts under `deploy/`. Use the
interactive cleanup prompt offered by either build wrapper, or run
`./scripts/cleanup.sh` when you have confirmed that no artifact needs to be
retained.

## Publishing images

1. Publish and verify the intended OpenScan APT suite on the package build
   host. Use `stable` for a production image and `nightly` for a Develop image.
2. If an upstream pi-gen update is intentional, update and commit the
   submodule pointer:
   ```bash
   git submodule sync pi-gen
   git submodule update --remote --checkout pi-gen
   git add pi-gen
   git commit -m "Update pi-gen submodule"
   ```
3. Rebuild the target variants, validate the image on the appropriate camera
   hardware, and publish the selected artifacts from `deploy/`. Keep the raw
   `pi-gen/deploy/` output as build evidence, not as the primary release
   location.

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

- Accepts the native wrapper's positional arguments and flags (`--skip-cleanup`, `--with-develop`, `.env` paths or short names), plus `--develop-only`.
- `./build-all-docker.sh --develop-only imx519` builds only the nightly/develop variant and skips the stable image.
- Creates a temporary, per-camera config file with the resolved `STAGE_LIST`, `IMG_NAME`, and `TARGET_HOSTNAME`.
- Exposes work/deploy/cache directories via bind mounts (`$PI_GEN_DIR/work`, `$PI_GEN_DIR/deploy`, `.cache/pi-gen/apt`) so artifacts persist on the host.

Both scripts load the common stage list, append the camera stage from the
selected `build-configs/*.env`, and append `stage6-develop` only for a Develop
build. Stage 4 / Node-RED is a deprecated compatibility path and is not part of
the supported image release workflow.

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
