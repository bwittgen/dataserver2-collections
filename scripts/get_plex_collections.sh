#!/usr/bin/env bash
# List all collection names from a Plex library (e.g., Movies)
#
# Usage (Unraid console / any bash):
#   export PLEX_TOKEN="xxxxxxxxxxxxxxxx"
#   export PLEX_URL="http://dataserver2:32400"   # or http://IP:32400
#   bash scripts/get_plex_collections.sh -l "Movies"
#
# Or pass flags:
#   bash scripts/get_plex_collections.sh -u "http://dataserver2:32400" -t "xxxxxxxx" -l "Movies"
#
# Notes:
# - Requires curl (present on Unraid). No jq/xmllint required.
# - Prints one collection name per line.

set -euo pipefail

PLEX_URL=${PLEX_URL:-"http://dataserver2:32400"}
PLEX_TOKEN=${PLEX_TOKEN:-"ahr6jCVZQ9gxTEgp5bBd"}
LIBRARY_NAME="Movies"

while getopts ":u:t:l:h" opt; do
  case $opt in
    u) PLEX_URL="$OPTARG" ;;
    t) PLEX_TOKEN="$OPTARG" ;;
    l) LIBRARY_NAME="$OPTARG" ;;
    h)
      echo "Usage: $0 [-u PLEX_URL] [-t PLEX_TOKEN] [-l LIBRARY_NAME]";
      exit 0;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
  esac
done

if [[ -z "${PLEX_TOKEN}" ]]; then
  echo "Error: Missing Plex token. Set PLEX_TOKEN env or use -t." >&2
  exit 1
fi

base="${PLEX_URL%/}"

curl_get() {
  local url="$1"
  curl -sS --fail --connect-timeout 10 --max-time 30 "$url"
}

# 1) Find library section key by name
sections_xml=$(curl_get "$base/library/sections?X-Plex-Token=$PLEX_TOKEN")
if [[ -z "$sections_xml" ]]; then
  echo "Error: No response from Plex at $base" >&2
  exit 1
fi

# Extract the section key for the given library name (attribute title="$LIBRARY_NAME")
section_key=$(awk -v lib="$LIBRARY_NAME" '
  /<Directory/ {
    line=$0;
    if (index(line, "title=\"" lib "\"")>0) {
      if (match(line, /key="[^"]+"/)) {
        k=substr(line, RSTART+5, RLENGTH-6);
        print k;
        exit
      }
    }
  }
' <<< "$sections_xml")

if [[ -z "$section_key" ]]; then
  echo "Error: Library '$LIBRARY_NAME' not found on server. Available libraries:" >&2
  echo "$sections_xml" | awk '
    /<Directory/ {
      if (match($0, /title="[^"]+"/)) {
        t=substr($0, RSTART+7, RLENGTH-8);
        print " - " t;
      }
    }
  ' >&2
  exit 1
fi

# 2) Page through collections in that section
start=0
size=200
found_any=0

while :; do
  # Query collections in this section; no type filter to ensure collections are returned
  url="$base/library/sections/$section_key/collections?X-Plex-Token=$PLEX_TOKEN&X-Plex-Container-Start=$start&X-Plex-Container-Size=$size"
  page=$(curl_get "$url" || true)
  # Stop if no response
  [[ -z "$page" ]] && break

  # Extract collection titles (Directory or Metadata elements with title="...")
  titles=$(awk '
    /<(Directory|Metadata)/ {
      if (match($0, /title="[^"]+"/)) {
        t=substr($0, RSTART+7, RLENGTH-8);
        print t;
      }
    }
  ' <<< "$page")

  if [[ -z "$titles" ]]; then
    break
  fi
  found_any=1
  printf "%s\n" "$titles"
  start=$(( start + size ))
done | awk '!seen[$0]++'

if (( found_any == 0 )); then
  # No collections found; exit quietly (non-error)
  exit 0
fi
