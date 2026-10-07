# Expects originals\<species>\<YYYY-MM-DD>\*.jpg
#   e.g. originals\great-egret\2026-10-05\IMG_4526.jpg
# The DATE comes from the folder name (camera clock is ignored).
# EXIF capture time is only used to order photos within a day.
# Writes photos\full\<species>\<date>\ and photos\thumb\<species>\<date>\,
# removes output for photos no longer in originals\, and rebuilds photos.json.
# Skips photos that already have output. Delete a photo's files in
# photos\full and photos\thumb to regenerate it.
# Requires ImageMagick 7 (`magick` on PATH).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$photos = @()
$keep = New-Object System.Collections.Generic.HashSet[string]

foreach ($sp in Get-ChildItem originals -Directory) {
  $species = $sp.Name.ToLower() -replace '\s+', '-'

  $strays = Get-ChildItem $sp.FullName -File
  if ($strays) {
    Write-Warning "Skipping $($strays.Count) loose file(s) in originals\$($sp.Name)\. Put them in a date folder, e.g. originals\$($sp.Name)\2026-10-05\"
  }

  foreach ($dd in Get-ChildItem $sp.FullName -Directory) {
    if ($dd.Name -notmatch '^\d{4}-\d{2}-\d{2}$') {
      Write-Warning "Skipping originals\$($sp.Name)\$($dd.Name): folder name must be YYYY-MM-DD"
      continue
    }
    $date = $dd.Name
    New-Item -ItemType Directory -Force "photos/full/$species/$date", "photos/thumb/$species/$date" | Out-Null

    $files = Get-ChildItem $dd.FullName -File |
      Where-Object { $_.Extension -match '^\.(jpe?g|png)$' } |
      Sort-Object Name

    foreach ($f in $files) {
      $n = $f.BaseName + ".jpg"
      $rel = "$species/$date/$n"
      $full = "photos/full/$rel"
      $thumb = "photos/thumb/$rel"
      [void]$keep.Add($full)
      [void]$keep.Add($thumb)

      if (-not (Test-Path $full)) {
        Write-Host "Processing $rel"
        magick $f.FullName -auto-orient -resize "1600x1600>" -colorspace sRGB -quality 82 $full
        magick $f.FullName -auto-orient -resize "600x600>" -colorspace sRGB -quality 80 $thumb
      }

      $dims = (magick identify -format "%w %h" $thumb) -split " "

      # Time of day from EXIF, used only for ordering within the day
      $raw = (magick identify -format "%[EXIF:DateTimeOriginal]" $f.FullName)
      if ($raw -match '^\d{4}:\d{2}:\d{2} (\d{2}:\d{2}:\d{2})') { $time = $Matches[1] } else { $time = "00:00:00" }

      $photos += [pscustomobject]@{
        species = $species
        file    = "$date/$n"
        taken   = "$date $time"
        w       = [int]$dims[0]
        h       = [int]$dims[1]
      }
    }
  }
}

# Remove output for photos that were renamed, moved, or deleted
if (Test-Path photos) {
  $root = (Resolve-Path photos).Path
  foreach ($p in Get-ChildItem photos -Recurse -File) {
    $rel = $p.FullName.Substring($root.Length + 1) -replace '\\', '/'
    if (-not $keep.Contains("photos/$rel")) {
      Remove-Item $p.FullName
      Write-Host "Removed stale photos/$rel"
    }
  }
  Get-ChildItem photos -Recurse -Directory |
    Sort-Object { $_.FullName.Length } -Descending |
    Where-Object { -not (Get-ChildItem $_.FullName -Force) } |
    Remove-Item
}

$json = ConvertTo-Json -InputObject @($photos) -Compress
[System.IO.File]::WriteAllText("$PSScriptRoot/photos.json", $json)
Write-Host "Wrote photos.json with $($photos.Count) photos"