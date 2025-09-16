#!/usr/bin/env bash
set -euo pipefail

# Prints each Radarr queue item with its quality name and resolution.
# Prefers RADARR_URL and RADARR_API_KEY env vars.
# Otherwise, attempts to parse them from a Kometa config YAML
# (default: /config/config.yml; override with KOMETA_CONFIG or --config path).

CONFIG_PATH="${KOMETA_CONFIG:-/config/config.yml}"
if [[ "${1:-}" == "--config" && -n "${2:-}" ]]; then
  CONFIG_PATH="$2"
fi

RADARR_URL_ENV="${RADARR_URL:-}"
RADARR_API_KEY_ENV="${RADARR_API_KEY:-}"

radarr_url="${RADARR_URL_ENV}"
radarr_key="${RADARR_API_KEY_ENV}"

# Lightweight YAML scan for radarr.url and radarr.token
if [[ -z "$radarr_url" || -z "$radarr_key" ]]; then
  if [[ -f "$CONFIG_PATH" ]]; then
    # shellcheck disable=SC2016
    radarr_url=$(awk '
      $0 ~ /^radarr:/ {in=1; next}
      in && $0 ~ /^[^[:space:]]/ {in=0}
      in && $0 ~ /^[[:space:]]+url:/ {
        gsub(/^[[:space:]]+url:[[:space:]]*/,"",$0); gsub(/"|\r/ ,"",$0); print $0; exit
      }
    ' "$CONFIG_PATH" || true)
    # shellcheck disable=SC2016
    radarr_key=$(awk '
      $0 ~ /^radarr:/ {in=1; next}
      in && $0 ~ /^[^[:space:]]/ {in=0}
      in && $0 ~ /^[[:space:]]+token:/ {
        gsub(/^[[:space:]]+token:[[:space:]]*/,"",$0); gsub(/"|\r/ ,"",$0); print $0; exit
      }
    ' "$CONFIG_PATH" || true)
  fi
fi

if [[ -z "$radarr_url" || -z "$radarr_key" ]]; then
  echo "Error: RADARR_URL/RADARR_API_KEY not set and unable to parse from config: $CONFIG_PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required for this script" >&2
  exit 1
fi

curl -sS -H "X-Api-Key: ${radarr_key}" \
  "${radarr_url%/}/api/v3/queue?page=1&pageSize=1000" \
| jq -r '
  ( .records // . )
  | map({ title: (.title // .series?.title // "unknown"),
          qname: (.quality.quality.name // "unknown"),
          res:   (.quality.quality.resolution // null) })
  | .[]
  | "\(.title) — \(.qname) — \((.res//"unknown")|tostring)p"'

