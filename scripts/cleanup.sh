#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PI_GEN_DIR="${PROJECT_ROOT}/pi-gen"
CACHE_DIR="${PROJECT_ROOT}/.cache"
WORK_DIR="${PI_GEN_DIR}/work"
DEPLOY_DIR="${PI_GEN_DIR}/deploy"

echo "=== OpenScan3 Build Cleanup ==="
echo ""
echo "This will remove:"
echo "  - Work directory: ${WORK_DIR}"
echo "  - Deploy directory: ${DEPLOY_DIR}"
echo "  - Cache directory: ${CACHE_DIR}"
echo "  - Docker image: pi-gen:latest"
echo "  - Docker containers: pigen_work*"
echo ""

# Check what exists
ITEMS_TO_CLEAN=()
[ -d "${WORK_DIR}" ] && ITEMS_TO_CLEAN+=("work")
[ -d "${DEPLOY_DIR}" ] && ITEMS_TO_CLEAN+=("deploy")
[ -d "${CACHE_DIR}" ] && ITEMS_TO_CLEAN+=("cache")

# Check Docker image
if command -v docker >/dev/null 2>&1; then
    if docker images pi-gen:latest -q 2>/dev/null | grep -q .; then
        ITEMS_TO_CLEAN+=("docker-image")
    fi
    
    # Check Docker containers
    if docker ps -a --filter name=pigen_work -q 2>/dev/null | grep -q .; then
        ITEMS_TO_CLEAN+=("docker-containers")
    fi
fi

if [ "${#ITEMS_TO_CLEAN[@]}" -eq 0 ]; then
    echo "Nothing to clean. All directories and Docker resources are already clean."
    exit 0
fi

echo "Found items to clean: ${ITEMS_TO_CLEAN[*]}"
echo ""

# Cleanup work directory
if [ -d "${WORK_DIR}" ]; then
    echo "Removing work directory..."
    rm -rf "${WORK_DIR}"
    echo "  ✓ Work directory removed"
fi

# Cleanup deploy directory
if [ -d "${DEPLOY_DIR}" ]; then
    echo "Removing deploy directory..."
    rm -rf "${DEPLOY_DIR}"
    echo "  ✓ Deploy directory removed"
fi

# Cleanup cache directory
if [ -d "${CACHE_DIR}" ]; then
    echo "Removing cache directory..."
    rm -rf "${CACHE_DIR}"
    echo "  ✓ Cache directory removed"
fi

# Cleanup Docker resources
if command -v docker >/dev/null 2>&1; then
    # Determine if we need sudo for docker
    DOCKER="docker"
    if ! ${DOCKER} ps >/dev/null 2>&1; then
        DOCKER="sudo docker"
    fi
    
    # Remove Docker containers
    CONTAINERS=$(${DOCKER} ps -a --filter name=pigen_work -q 2>/dev/null || true)
    if [ -n "${CONTAINERS}" ]; then
        echo "Removing Docker containers..."
        ${DOCKER} rm -f ${CONTAINERS}
        echo "  ✓ Docker containers removed"
    fi
    
    # Remove Docker image
    if ${DOCKER} images pi-gen:latest -q 2>/dev/null | grep -q .; then
        echo "Removing Docker image pi-gen:latest..."
        ${DOCKER} rmi pi-gen:latest
        echo "  ✓ Docker image removed"
    fi
fi

echo ""
echo "=== Cleanup complete ==="
