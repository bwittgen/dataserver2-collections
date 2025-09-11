#!/usr/bin/env bash
set -euo pipefail

# One-shot Kometa runner
# - Prefers local `kometa` install if present
# - Falls back to Docker image `ghcr.io/kometateam/kometa:latest`
# - Configure via env vars or defaults below

# Configuration
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${TZ:=UTC}"

# Path to Kometa config on the HOST (override if yours differs)
# Common locations:
#  - ~/.config/kometa/config.yml (recommended default)
#  - $SCRIPT_DIR/config/kometa.yml (project-local)
HOST_CONFIG_PATH="${CONFIG_PATH:-$HOME/.config/kometa/config.yml}"

if [[ ! -f "$HOST_CONFIG_PATH" ]]; then
  echo "[WARN] Kometa config not found at: $HOST_CONFIG_PATH" >&2
  echo "       Set CONFIG_PATH=/path/to/config.yml when invoking this script." >&2
fi

run_local() {
  echo "[INFO] Running Kometa locally (once) with config: $HOST_CONFIG_PATH"
  kometa --config "$HOST_CONFIG_PATH"
}

run_local_python() {
  echo "[INFO] Running Kometa via python -m (once) with config: $HOST_CONFIG_PATH"
  python -m kometa --config "$HOST_CONFIG_PATH"
}

run_docker() {
  echo "[INFO] Running Kometa via Docker (once)"
  # Mount host config directory to /config inside the container
  host_config_dir="$(cd "$(dirname "$HOST_CONFIG_PATH")" 2>/dev/null || echo "$HOME/.config/kometa")"
  docker run --rm \
    --name kometa-one-shot \
    -e TZ="$TZ" \
    -v "$host_config_dir":/config:rw \
    -v "$SCRIPT_DIR":/collections:ro \
    ghcr.io/kometateam/kometa:latest
}

main() {
  if command -v kometa >/dev/null 2>&1; then
    run_local
    exit 0
  fi

  if command -v python >/dev/null 2>&1; then
    # Try python -m kometa if the module is installed
    if python - <<'PY' 2>/dev/null; then
import importlib
import sys
try:
    importlib.import_module('kometa')
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
    then
      run_local_python
      exit 0
    fi
  fi

  if command -v docker >/dev/null 2>&1; then
    run_docker
    exit 0
  fi

  echo "[ERROR] Could not find a way to run Kometa." >&2
  echo "        Install kometa (pip/pipx), or Docker, or set PATH accordingly." >&2
  exit 1
}

main "$@"

