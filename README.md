# dataserver2-collections
Hosts plex collections for dataserver2
TVShows.yml for TV shows
Movies.yml for movies

Rest are just samples/things I am playing with but not in production. If you wish to create/add a new .yml, let me know

Kometa Wiki here:
https://kometa.wiki/en/latest/

chat.openai.com is great for iterating on this and generating lists

## Run on Unraid

- Script: `./run-kometa.sh` runs Kometa one time on demand.
- Defaults (override via env vars when running):
  - `KOMETA_APPDATA=/mnt/cache/appdata/Kometa/config`
  - `CONFIG_PATH=$KOMETA_APPDATA` (can be a directory with `config.yml` inside, or a direct file path)
  - `CONTAINER_NAME=Kometa`
  - `IN_CONTAINER_CONFIG=/config/config.yml`
  - `DOCKER_IMAGE=ghcr.io/kometateam/kometa:latest` (only used if no container named `CONTAINER_NAME` exists)

### Examples

- Run with defaults inside existing container:
  - `./run-kometa.sh`

- Use a different container name:
  - `CONTAINER_NAME=my-kometa ./run-kometa.sh`

- Point to a non-default config path:
  - Directory: `CONFIG_PATH=/mnt/cache/appdata/Kometa/config ./run-kometa.sh`
  - File: `CONFIG_PATH=/mnt/user/appdata/Kometa/config/config.yml ./run-kometa.sh`

- Use a mirrored image if GHCR requires login:
  - `DOCKER_IMAGE=myregistry/kometa:latest ./run-kometa.sh`

If using GHCR and you see a permission error, authenticate once:

```
export CR_PAT=YOUR_GITHUB_TOKEN   # scope: read:packages
echo $CR_PAT | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```
