<#!
Synopsis: List all collection names from a Plex library (e.g., Movies)

Usage examples:

  # Using env var PLEX_TOKEN
  # PowerShell (Windows/macOS/Linux)
  $env:PLEX_TOKEN = "xxxxxxxxxxxxxxxxxxxx"
  .\scripts\Get-PlexCollectionNames.ps1 -Server "http://127.0.0.1:32400" -LibraryName "Movies"

  # Or pass token explicitly
  .\scripts\Get-PlexCollectionNames.ps1 -Server "http://your-plex:32400" -Token "xxxxxxxx" -LibraryName "Movies"

Outputs one collection name per line.
#!>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)] [string]$Server = "http://dataserver2:32400",
  [Parameter(Mandatory=$false)] [string]$Token = $env:PLEX_TOKEN,
  [Parameter(Mandatory=$false)] [string]$LibraryName = "Movies",
  [switch]$AsJson
)

function Invoke-PlexRequest {
  param(
    [Parameter(Mandatory=$true)] [string]$Uri
  )
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 30
    return $resp.Content
  }
  catch {
    throw "Plex request failed: $Uri`n$($_.Exception.Message)"
  }
}

if (-not $Token -or [string]::IsNullOrWhiteSpace($Token)) {
  # Default token inserted per user request
  $Token = "ahr6jCVZQ9gxTEgp5bBd"
}

$base = $Server.TrimEnd('/')

# 1) Find the library section key by name
$sectionsUri = "$base/library/sections?X-Plex-Token=$Token"
$sectionsXml = [xml](Invoke-PlexRequest -Uri $sectionsUri)
if (-not $sectionsXml.MediaContainer.Directory) {
  throw "No library sections returned from Plex at $Server"
}

$section = $sectionsXml.MediaContainer.Directory | Where-Object { $_.title -eq $LibraryName } | Select-Object -First 1
if (-not $section) {
  $available = ($sectionsXml.MediaContainer.Directory | ForEach-Object { $_.title }) -join ', '
  throw "Library '$LibraryName' not found. Available: $available"
}

$sectionKey = $section.key

# 2) Page through collections in that section
$start = 0
$size = 200
$names = New-Object System.Collections.Generic.List[string]

while ($true) {
  $collectionsUri = "$base/library/sections/$sectionKey/collections?type=1&X-Plex-Token=$Token&X-Plex-Container-Start=$start&X-Plex-Container-Size=$size"
  $xml = [xml](Invoke-PlexRequest -Uri $collectionsUri)

  $mc = $xml.MediaContainer
  if (-not $mc) { break }

  $meta = @()
  if ($mc.Metadata) { $meta = @($mc.Metadata) }

  foreach ($m in $meta) {
    if ($m.title) { [void]$names.Add([string]$m.title) }
  }

  $total = [int]($mc.totalSize ? $mc.totalSize : ($mc.size ? $mc.size : 0))
  if ($total -le 0 -or $meta.Count -lt 1) { break }
  $start += $size
  if ($start -ge $total) { break }
}

if ($AsJson) {
  $names | Sort-Object -Unique | ConvertTo-Json -Depth 3
}
else {
  $names | Sort-Object -Unique | ForEach-Object { $_ }
}
