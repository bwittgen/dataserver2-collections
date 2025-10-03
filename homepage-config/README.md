# Homepage Dashboard Configuration

This directory contains configuration files for [Homepage](https://gethomepage.dev/) dashboard.

## Services Configuration

The `services.yaml` file includes configuration for the following media management services with Queue and Logs navigation items:

- **Sonarr** (TV Show Management)
  - Queue: View current download queue
  - Logs: View system logs
  
- **Radarr** (Movie Management)
  - Queue: View current download queue
  - Logs: View system logs
  
- **Bazarr** (Subtitle Management)
  - Queue: View download history
  - Logs: View system logs
  
- **Whisparr** (Adult Content Management)
  - Queue: View current download queue
  - Logs: View system logs

## Installation

1. Copy the `services.yaml` file to your Homepage configuration directory (typically `/config` in the Homepage container)
2. Set the following environment variables in your Homepage container:
   - `HOMEPAGE_VAR_SONARR_API_KEY` - Your Sonarr API key
   - `HOMEPAGE_VAR_RADARR_API_KEY` - Your Radarr API key
   - `HOMEPAGE_VAR_BAZARR_API_KEY` - Your Bazarr API key
   - `HOMEPAGE_VAR_WHISPARR_API_KEY` - Your Whisparr API key

3. Adjust the URLs in `services.yaml` if your services are running on different hosts or ports

## Configuration Details

Each service includes:
- **Main link**: Direct access to the service web interface
- **Widget**: Shows service statistics on the dashboard
- **Queue submenu**: Quick access to the download queue
- **Logs submenu**: Quick access to system logs

## Default URLs

The configuration assumes services are running on `dataserver2` with the following default ports:
- Sonarr: 8989
- Radarr: 7878
- Bazarr: 6767
- Whisparr: 6969

Adjust these in `services.yaml` if your setup differs.

## API Keys

API keys for each service can be found in their respective settings:
- Navigate to Settings → General → Security → API Key in each service's web interface

## Troubleshooting

If widgets don't display:
1. Verify API keys are correctly set in environment variables
2. Ensure URLs are accessible from the Homepage container
3. Check Homepage logs for any connection errors
4. Verify the services are running and accessible
