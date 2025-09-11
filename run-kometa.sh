#!/usr/bin/env bash
set -euo pipefail

# One-shot Kometa runner (Unraid-friendly)
# - Prefers executing inside existing Kometa container
# - Starts the container if stopped
# - Falls back to running the image with your appdata bound
# - Configure via env vars or defaults below

# Configuration
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${TZ:=UTC}"
# Appdata on Unraid (host path to Kometa config directory)
# Example structure: /mnt/cache/appdata/Kometa/config/config.yml
: "${KOMETA_APPDATA:=/mnt/cache/appdata/Kometa/config}"
# Default host config path (directory or file). If directory, script uses config.yml inside it.
: "${CONFIG_PATH:=$KOMETA_APPDATA}"
# Existing container name (as shown in Unraid Docker tab)
: "${CONTAINER_NAME:=Kometa}"
# Path to config inside the container
: "${IN_CONTAINER_CONFIG:=/config/config.yml}"
# Docker image (used only if container is not found)
: "${DOCKER_IMAGE:=ghcr.io/kometateam/kometa:latest}"

if [[ -d "$CONFIG_PATH" ]]; then
  if [[ ! -f "$CONFIG_PATH/config.yml" ]]; then
    echo "[WARN] Kometa config directory found but missing config.yml: $CONFIG_PATH" >&2
    echo "       Ensure $CONFIG_PATH/config.yml exists or set CONFIG_PATH to a file path." >&2
  fi
elif [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[WARN] Kometa config not found at: $CONFIG_PATH" >&2
  echo "       Set CONFIG_PATH to a config directory or config.yml file path." >&2
fi

run_docker_image() {
  echo "[INFO] Running Kometa via Docker image (once)"
  local host_config_dir
  if [[ -d "$CONFIG_PATH" ]]; then
    host_config_dir="$CONFIG_PATH"
  else
    host_config_dir="$(cd "$(dirname "$CONFIG_PATH")" 2>/dev/null || echo "$KOMETA_APPDATA")"
  fi
  # Pre-pull to surface auth errors early
  if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    if ! docker pull "$DOCKER_IMAGE"; then
      echo "[ERROR] Unable to pull Docker image: $DOCKER_IMAGE" >&2
      echo "        If using ghcr.io, authenticate with a GitHub Personal Access Token (scope: read:packages):" >&2
      echo "          export CR_PAT=YOUR_GITHUB_TOKEN" >&2
      echo "          echo \$CR_PAT | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin" >&2
      echo "        Then rerun this script, or set DOCKER_IMAGE to an accessible mirror." >&2
      exit 1
    fi
  fi
  docker run --rm \
    --name kometa-one-shot \
    -e TZ="$TZ" \
    -v "$host_config_dir":/config:rw \
    -v "$SCRIPT_DIR":/collections:ro \
    "$DOCKER_IMAGE"
}

run_in_container() {
  echo "[INFO] Running Kometa inside container: $CONTAINER_NAME"
  docker exec "$CONTAINER_NAME" kometa --config "$IN_CONTAINER_CONFIG"
}

main() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] Docker is required to run this script on Unraid." >&2
    exit 1
  fi

  local exists running
  exists=false; running=false
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then exists=true; fi
  if docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then running=true; fi

  if [[ "$exists" == true ]]; then
    if [[ "$running" != true ]]; then
      echo "[INFO] Starting container: $CONTAINER_NAME"
      docker start "$CONTAINER_NAME" >/dev/null
    fi
    run_in_container
    exit 0
  fi

  echo "[INFO] Container '$CONTAINER_NAME' not found; running image instead."
  run_docker_image
}

main "$@"
