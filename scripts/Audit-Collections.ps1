<#
Audits Movies.yml collections for structural and content consistency.

Checks
- Group headers present: Directors, Writers, Studios, Special Genres, Franchise Collections, Originals, Charts, Best Of, Other Collections
- No duplicate top-level collection keys within each group
- Alphabetical order of keys within each group
- Per-group required fields:
  - Directors: template → name: Director, tmdb: <id>
  - Writers: template → name: Writer, writer: <id>
  - Studios: template → name: Studio
  - Special Genres: template → name: Special Genre
  - Franchise Collections: template → name: Movies, exactly one numeric collection id
  - Originals: exactly these blocks only — Amazon/Apple/Netflix/HBO Max/HULU Originals 2021-2025
  - Charts: template present
  - Best Of: template → name: Best of, year: <yyyy>
  - Other Collections: template present (best-effort)
- Flags risky keys (unquoted headers containing additional ':' characters)

Usage
  pwsh ./scripts/Audit-Collections.ps1 -File 'Movies.yml'
  pwsh ./scripts/Audit-Collections.ps1 -File 'Movies.yml' -FailOnIssues
#!>

[CmdletBinding()]
param(
  [string]$File = 'Movies.yml',
  [switch]$FailOnIssues
)

if (-not (Test-Path $File)) { throw "File not found: $File" }

$lines = Get-Content -Path $File

# Discover group headers
$groupMatches = Select-String -Path $File -Pattern '^\s*#\s*(Directors|Writers|Studios|Special Genres|Franchise Collections|Originals|Charts|Best Of|Other Collections)\s*$'
if (-not $groupMatches) { throw "No known group headers found in $File" }

function Get-SectionRange {
  param([int]$Start)
  $end = $lines.Count - 1
  for ($i = $Start + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*#\s+') { $end = $i - 1; break }
  }
  ,@($Start, $end)
}

function Parse-Blocks {
  param([int]$S, [int]$E)
  $section = $lines[$S..$E]
  $blocks = @()
  for ($i = 1; $i -lt $section.Count; $i++) {
    if ($section[$i] -match '^  [^#\s].*:\s*$') {
      $start = $i
      $j = $i + 1
      while ($j -lt $section.Count -and -not ($section[$j] -match '^  [^#\s].*:\s*$')) { $j++ }
      $endb = $j - 1
      $name = ($section[$i].TrimEnd(':')).Trim()
      $seg = $section[$start..$endb]
      $blocks += [pscustomobject]@{ name=$name; seg=$seg; start=$S + $start; end=$S + $endb }
      $i = $endb
    }
  }
  ,$blocks
}

$report = @()

foreach ($gm in $groupMatches) {
  $header = $gm.Matches.Value.Trim('# ').Trim()
  $S = $gm.LineNumber - 1
  $range = Get-SectionRange -Start $S
  $blocks = Parse-Blocks -S $range[0] -E $range[1]

  # Duplicates
  $dups = ($blocks.name | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  foreach ($d in $dups) { $report += [pscustomobject]@{ group=$header; name=$d; issue='Duplicate key in group' } }

  # Alphabetical
  $alpha = ($blocks.name -join '|') -eq ((($blocks.name | Sort-Object) -join '|'))
  if (-not $alpha) { $report += [pscustomobject]@{ group=$header; name='(group)'; issue='Not alphabetical' } }

  switch ($header) {
    'Directors' {
      foreach ($b in $blocks) {
        $hasName = $false; $hasTmdb = $false
        foreach ($ln in $b.seg) {
          if ($ln -match '^\s{6}name:\s*Director\s*$') { $hasName = $true }
          if ($ln -match '^\s{6}tmdb:\s*\d+\s*$') { $hasTmdb = $true }
        }
        if (-not $hasName -or -not $hasTmdb) { $report += [pscustomobject]@{ group=$header; name=$b.name; issue='Director template missing name or tmdb' } }
      }
    }
    'Writers' {
      foreach ($b in $blocks) {
        $hasName = $false; $hasWriter = $false
        foreach ($ln in $b.seg) {
          if ($ln -match '^\s{6}name:\s*Writer\s*$') { $hasName = $true }
          if ($ln -match '^\s{6}writer:\s*\d+\s*$') { $hasWriter = $true }
        }
        if (-not $hasName -or -not $hasWriter) { $report += [pscustomobject]@{ group=$header; name=$b.name; issue='Writer template missing name or writer id' } }
      }
    }
    'Studios' {
      foreach ($b in $blocks) { if (-not ($b.seg -match '^\s{6}name:\s*Studio\s*$')) { $report += [pscustomobject]@{ group=$header; name=$b.name; issue='Studio template missing' } } }
    }
    'Special Genres' {
      foreach ($b in $blocks) { if (-not ($b.seg -match '^\s{6}name:\s*Special Genre\s*$')) { $report += [pscustomobject]@{ group=$header; name=$b.name; issue='Special Genre template missing' } } }
    }
    'Franchise Collections' {
      foreach ($b in $blocks) {
        $hasTemplate = ($b.seg -match '^\s{4}template:')
        $hasMovies = ($b.seg -match '^\s{6}name:\s*Movies\s*$')
        $ids = @(); foreach ($ln in $b.seg) { if ($ln -match '^\s{6}collection:\s*(\d+)\s*$') { $ids += $Matches[1] } }
        if (-not $hasTemplate -or -not $hasMovies -or $ids.Count -ne 1) { $report += [pscustomobject]@{ group=$header; name=$b.name; issue=('Franchise block missing fields or invalid ids: [{0}]' -f ($ids -join ',')) } }
      }
    }
    'Originals' {
      $allowed = @('Amazon Originals 2021-2025','Apple Originals 2021-2025','Netflix Originals 2021-2025','HBO Max Originals 2021-2025','HULU Originals 2021-2025')
      $present = $blocks.name
      foreach ($n in ($present | Where-Object { $_ -notin $allowed })) { $report += [pscustomobject]@{ group=$header; name=$n; issue='Unexpected block in Originals' } }
      foreach ($a in $allowed) { if ($present -notcontains $a) { $report += [pscustomobject]@{ group=$header; name=$a; issue='Missing Originals block' } } }
    }
    'Charts' {
      foreach ($b in $blocks) { if (-not ($b.seg -match '^\s{4}template:')) { $report += [pscustomobject]@{ group=$header; name=$b.name; issue='Chart missing template' } } }
    }
    'Best Of' {
      foreach ($b in $blocks) {
        $hasBest = ($b.seg -match '^\s{6}name:\s*Best of\s*$')
        $hasYear = ($b.seg -match '^\s{6}year:\s*\d{4}\s*$')
        if (-not $hasBest -or -not $hasYear) { $report += [pscustomobject]@{ group=$header; name=$b.name; issue='Best Of missing template name or year' } }
      }
    }
    'Other Collections' {
      foreach ($b in $blocks) { if (-not ($b.seg -match '^\s{4}template:')) { $report += [pscustomobject]@{ group=$header; name=$b.name; issue='Other: missing template' } } }
    }
  }
}

# Warn about risky keys (headers with additional ':')
$risky = Select-String -Path $File -Pattern '^  (.+):\s*$' | Where-Object { ($_.Matches.Groups[1].Value) -match ':' -and ($_.Matches.Groups[1].Value) -notmatch "^'.*'") }
foreach ($rk in $risky) { $report += [pscustomobject]@{ group='(keys)'; name=$rk.Matches.Groups[1].Value; issue='Header key contains colon and is not quoted' } }

if ($report.Count -gt 0) {
  $report | Sort-Object group,name | Format-Table -AutoSize | Out-String | Write-Output
  if ($FailOnIssues) { exit 1 }
} else {
  Write-Output 'All audited sections look good.'
}

