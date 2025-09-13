<#
Converts Movies-template plex_search collections in Movies.yml to TMDb collection IDs.

Requirements:
- TMDb API key in env var TMDB_API_KEY (or pass -ApiKey)

Usage:
  # Dry run
  # $env:TMDB_API_KEY = 'your_key'
  # pwsh ./scripts/Resolve-TmdbCollections.ps1 -File 'Movies.yml' -WhatIf

  # Write changes
  # pwsh ./scripts/Resolve-TmdbCollections.ps1 -File 'Movies.yml'

It will:
- Find collections using template: name: Movies that have plex_search and no collection id
- Search TMDb for a matching collection id
- Insert 'collection: <id>' under the template block
- Remove the plex_search block
- Keep everything else untouched and alphabetic order preserved
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$File = 'Movies.yml',
  [string]$ApiKey = $env:TMDB_API_KEY
)

if (-not (Test-Path $File)) { throw "File not found: $File" }
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "Missing TMDb API key. Set TMDB_API_KEY or pass -ApiKey" }

function NormalizeSlug([string]$s){ return (-join (($s -replace '\\(.*?\\)','' ).ToLower() -replace '[^a-z0-9]+','-')).Trim('-') }

function Find-TmdbCollectionId {
  param([Parameter(Mandatory)] [string]$Name)
  $query = $Name -replace "^'|'$","" -replace ' Collection$',''
  $uri = "https://api.themoviedb.org/3/search/collection?api_key=$ApiKey`&language=en-US`&query=$([uri]::EscapeDataString($query))"
  try { $res = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 20 } catch { return $null }
  if (-not $res.results) { return $null }
  $nb = NormalizeSlug $query
  $scored = foreach ($r in $res.results) {
    $slug = NormalizeSlug $r.name
    $score = 0
    if ($slug -eq ($nb + '-collection')) { $score = 100 }
    elseif ($slug -like ('*' + $nb + '*')) { $score = 80 }
    elseif ($r.name -like ($query + '*')) { $score = 60 }
    [pscustomobject]@{ id=$r.id; name=$r.name; score=$score }
  }
  $pick = $scored | Sort-Object score -Descending | Select-Object -First 1
  if ($pick.score -lt 60) { return $null }
  return $pick.id
}

$lines = [System.Collections.Generic.List[string]](Get-Content -Path $File)
$candidates = @()
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^  [^#\s].*:\s*$') {
    $start = $i; $j = $i + 1
    while ($j -lt $lines.Count -and -not ($lines[$j] -match '^  [^#\s].*:\s*$')) { $j++ }
    $end = $j - 1
    $seg = $lines[$start..$end]
    $name = ($lines[$i].TrimEnd(':')).Trim()
    $hasTemplate = $false; $isMovies = $false; $hasCollection = $false; $plexIdx = -1; $tmplIdx = -1; $nameIdx = -1
    for ($k=0; $k -lt $seg.Count; $k++) {
      if ($seg[$k] -match '^\s{4}template:\s*$') { $hasTemplate=$true; $tmplIdx=$k }
      if ($seg[$k] -match '^\s{6}name:\s*Movies\s*$' -and $hasTemplate) { $isMovies=$true; $nameIdx=$k }
      if ($seg[$k] -match '^\s{6}collection:\s*\d') { $hasCollection=$true }
      if ($seg[$k] -match '^\s{4}plex_search:\s*$') { $plexIdx=$k }
    }
    if ($isMovies -and -not $hasCollection -and $plexIdx -ge 0) {
      $candidates += [pscustomobject]@{ start=$start; end=$end; name=$name; seg=$seg; plexIdx=$plexIdx; tmplIdx=$tmplIdx; nameIdx=$nameIdx }
    }
    $i = $end
  }
}

if ($candidates.Count -eq 0) {
  Write-Output 'No plex_search-only Movies-template collections found.'
  exit 0
}

$resolved = @()
foreach ($c in $candidates) {
  Start-Sleep -Milliseconds 200
  $id = Find-TmdbCollectionId -Name $c.name
  $resolved += [pscustomobject]@{ name=$c.name; id=$id; block=$c }
}

$changes = 0
foreach ($r in $resolved) {
  if (-not $r.id) { Write-Warning "No TMDb collection found for '$($r.name)'"; continue }
  $b = $r.block
  $seg = [System.Collections.Generic.List[string]]($b.seg)
  $pi = $b.plexIdx
  $removeCount = 1
  for ($m = $pi + 1; $m -lt $seg.Count; $m++) {
    if ($seg[$m] -match '^\s{2}[^\s]') { break }
    if ($seg[$m] -match '^\s{4}[^\s]') { break }
    $removeCount++
  }
  $seg.RemoveRange($pi, $removeCount)
  $insertAt = if ($b.nameIdx -ge 0) { $b.nameIdx + 1 } elseif ($b.tmplIdx -ge 0) { $b.tmplIdx + 1 } else { 1 }
  $seg.Insert($insertAt, ("      collection: {0}" -f $r.id))
  if ($PSCmdlet.ShouldProcess($r.name, ("Set collection id {0} and remove plex_search" -f $r.id))) {
    $count = $b.end - $b.start + 1
    $lines.RemoveRange($b.start, $count)
    $lines.InsertRange($b.start, $seg)
    $changes++
  }
}

if ($changes -gt 0 -and -not $WhatIfPreference) {
  Set-Content -Path $File -Value $lines
}

Write-Output ("UPDATED: {0}, UNRESOLVED: {1}" -f $changes, ($resolved | Where-Object { -not $_.id }).Count)
