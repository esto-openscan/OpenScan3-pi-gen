# OpenScan3 Pi Image Builder

This repository wraps [Raspberry Pi OS pi-gen](https://github.com/RPi-Distro/pi-gen) as a submodule and adds custom stages for OpenScan3 camera setups. It produces Raspberry Pi OS Lite based images with camera-specific tweaks and the OpenScan3 firmware.

## Repository Layout

- `pi-gen/` &mdash; upstream pi-gen submodule. Do not modify directly; keep customizations outside.
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
```

## Building Images

Use `build-all.sh` to build one or more camera variants.

```bash
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

## Build in Docker

You can run the build inside Docker for better host isolation and cross-distro support.

Prerequisites:

- Ensure Docker can run privileged containers.
- On non-ARM hosts, make sure binfmt support is enabled and `qemu-user-static` is installed on the host before starting the Docker build.

Quick start:

```bash
# make wrapper executable (once)
chmod +x build-all-docker.sh

# build a single variant by short name
./build-all-docker.sh generic

# build by providing explicit env file path
./build-all-docker.sh camera-configs/imx519.env

# build multiple variants in sequence
./build-all-docker.sh generic imx519

# build every available variant (default when no args given)
./build-all-docker.sh
```

Notes:

- The wrapper generates a per-camera `config` for `pi-gen` and mounts this repo into the container at `/project` so that custom stages like `stage3-openscan/...` are available.
- The container name is printed during each build (format: `pigen_work_<camera>`). This helps with troubleshooting.
- After a successful Docker build, artifacts and logs are extracted to `deploy/` at the repository root.
  - Native (non-Docker) builds place artifacts under `pi-gen/deploy/`.

Continuing or preserving Docker builds:

```bash
# continue an interrupted build (reuses existing container)
CONTINUE=1 ./build-all-docker.sh generic

# prevent container removal to speed up incremental iterations
PRESERVE_CONTAINER=1 ./build-all-docker.sh generic
```

Inspecting a preserved container:

```bash
# replace <camera> with the printed camera name (e.g. generic, imx519)
sudo docker run -it --privileged --volumes-from=pigen_work_<camera> pi-gen /bin/bash
```

Passing extra Docker options:

```bash
# e.g., add an /etc/hosts entry inside the container
PIGEN_DOCKER_OPTS="--add-host foo:192.168.0.23" ./build-all-docker.sh generic
```

Advanced: Use pi-gen directly with a single config file

If you prefer not to use the wrapper, you can write a `config` file and call `pi-gen/build-docker.sh -c <path>`. Ensure `STAGE_LIST` uses container-visible paths:

```bash
# inside your config
IMG_NAME="your-image-name"
# stock stages come from /pi-gen; custom stages from this repo are under /project
STAGE_LIST="/pi-gen/stage0 /pi-gen/stage1 /pi-gen/stage2 /project/stage3-openscan/00-base"

# run the docker build directly
./pi-gen/build-docker.sh -c /absolute/path/to/your/config
```

CAUTION (from pi-gen docs): `BASE_DIR` is derived from the `pi-gen/` location; changing it will likely break `build.sh`. Keep customizations outside the `pi-gen/` submodule and reference them via `STAGE_LIST`.

## Customizing Stages

1. Add new stage directories inside `stage3-openscan/` following the pi-gen stage layout (`00-config`, `01-run.sh`, etc.).
2. Reference those stages in the desired `STAGE_LIST` within a camera config.
3. Keep upstream `pi-gen` untouched; commit your changes outside the submodule.

## Cleaning Up

Native builds create work under `pi-gen/work/` and images under `pi-gen/deploy/`.

Docker builds extract artifacts to `deploy/` at the repository root and keep work data inside the container. Remove them when no longer needed:

```bash
rm -rf pi-gen/work pi-gen/deploy
# if you used Docker builds and want to clean extracted artifacts
rm -rf deploy
```

## Releasing Updates

1. Pull upstream `pi-gen` updates:
   ```bash
   git submodule update --remote --merge
   ```
2. Rebuild target images.
3. Publish resulting `.img` files from `pi-gen/deploy/`.
