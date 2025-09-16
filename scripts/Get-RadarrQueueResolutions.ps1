Param(
  [string]$ConfigPath = $env:KOMETA_CONFIG,
  [string]$Url = $env:RADARR_URL,
  [string]$ApiKey = $env:RADARR_API_KEY
)

function Get-RadarrFromConfig([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $lines = Get-Content -LiteralPath $path
  $in = $false
  $url = $null
  $token = $null
  foreach ($ln in $lines) {
    if ($ln -match '^radarr:\s*$') { $in = $true; continue }
    if ($in -and $ln -match '^[^\s]') { $in = $false }
    if (-not $in) { continue }
    if ($ln -match '^\s+url:\s*(.+)')   { $url = $Matches[1].Trim() }
    if ($ln -match '^\s+token:\s*(.+)') { $token = $Matches[1].Trim() }
  }
  if ($url -and $token) { return @{ url = $url; token = $token } }
  return $null
}

# Resolve config path default if not provided
if (-not $ConfigPath -or $ConfigPath -eq '') {
  # Try common Kometa container path first, then Windows path
  if (Test-Path -LiteralPath '/config/config.yml') { $ConfigPath = '/config/config.yml' }
  elseif (Test-Path -LiteralPath 'Z:\\configLive\\config.yml') { $ConfigPath = 'Z:\\configLive\\config.yml' }
}

if (-not $Url -or -not $ApiKey) {
  $cfg = Get-RadarrFromConfig -path $ConfigPath
  if ($cfg) {
    if (-not $Url)   { $Url = $cfg.url }
    if (-not $ApiKey){ $ApiKey = $cfg.token }
  }
}

if (-not $Url)   { throw 'Set RADARR_URL, or pass -Url, or provide a config with radarr.url' }
if (-not $ApiKey){ throw 'Set RADARR_API_KEY, or pass -ApiKey, or provide a config with radarr.token' }

$headers = @{ 'X-Api-Key' = $ApiKey }

try {
  $resp = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri ("{0}/api/v3/queue?page=1&pageSize=1000" -f $Url.TrimEnd('/')) -TimeoutSec 30
} catch {
  throw "Failed to query Radarr queue: $_"
}

$items = if ($resp.PSObject.Properties.Name -contains 'records') { $resp.records } else { $resp }

$items | ForEach-Object {
  $title = $_.title
  if (-not $title) { $title = $_.movie?.title }
  if (-not $title) { $title = $_.series?.title }
  $qname = $_.quality.quality.name
  $qres  = $_.quality.quality.resolution

  # Look up existing on-disk movie file (if any)
  $existingQ = ''
  $existingR = ''
  $existingP = ''
  $mid = $_.movieId
  if ($mid) {
    try {
      $mfiles = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri ("{0}/api/v3/moviefile?movieId={1}" -f $Url.TrimEnd('/'), $mid) -TimeoutSec 30
      if ($mfiles) {
        $mf = $mfiles | Sort-Object size -Descending | Select-Object -First 1
        if ($mf) {
          $existingQ = $mf.quality.quality.name
          $existingR = $mf.quality.quality.resolution
          $existingP = if ($mf.path) { $mf.path } else { $mf.relativePath }
        }
      }
    } catch {
      # ignore
    }
  }

  '{0} — {1} — {2}p — {3} — {4}p — {5}' -f \
    ($title ?? 'unknown'), ($qname ?? 'unknown'), ($qres ?? 'unknown'), \
    ($existingQ ?? ''),     ($existingR ?? ''),     ($existingP ?? '')
}
