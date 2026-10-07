# Reads originals/<species>/*.{jpg,jpeg,png}, writes photos/full/<species>/ (1600px)
# and photos/thumb/<species>/ (600px), regenerates photos.json.
# taken = EXIF DateTimeOriginal, falling back to the file's modified time.
# Folder name under originals/ is used verbatim as the species slug
# (use lowercase-hyphen names, e.g. great-egret).
# Skips photos that already have output. Delete a photo's files in
# photos/full and photos/thumb to regenerate it.
# Requires ImageMagick 7 (`magick` on PATH).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Camera-clock corrections: species slug -> real capture date ("YYYY-MM-DD").
# Applied on top of the EXIF time-of-day. Remove an entry once the EXIF in
# originals/ is fixed. One date per species: photos from different trips of
# the same species collapse onto one day.
$takenDateOverride = @{
  "great-egret" = "2026-10-05"
}

New-Item -ItemType Directory -Force photos/full, photos/thumb | Out-Null

$entries = @()
Get-ChildItem originals -Directory | Sort-Object Name | ForEach-Object {
  $species = $_.Name
  Get-ChildItem $_.FullName -File |
    Where-Object { $_.Extension -match '^\.(jpe?g|png)$' } |
    Sort-Object Name |
    ForEach-Object {
      $n = $_.BaseName + ".jpg"
      $fullDir = "photos/full/$species"
      $thumbDir = "photos/thumb/$species"
      $full = "$fullDir/$n"
      $thumb = "$thumbDir/$n"
      New-Item -ItemType Directory -Force $fullDir, $thumbDir | Out-Null

      if (-not (Test-Path $full)) {
        Write-Host "Processing $species/$n"
        magick $_.FullName -auto-orient -resize "1600x1600>" -colorspace sRGB -quality 82 $full
        magick $_.FullName -auto-orient -resize "600x600>" -colorspace sRGB -quality 80 $thumb
      }

      $exif = magick identify -format "%[EXIF:DateTimeOriginal]" $_.FullName
      if ($exif -match '(\d{4}):(\d{2}):(\d{2}) (\d{2}:\d{2}:\d{2})') {
        $date = if ($takenDateOverride.ContainsKey($species)) { $takenDateOverride[$species] } else { "$($Matches[1])-$($Matches[2])-$($Matches[3])" }
        $taken = "$date $($Matches[4])"
      } elseif ($takenDateOverride.ContainsKey($species)) {
        $taken = "$($takenDateOverride[$species]) $($_.LastWriteTime.ToString('HH:mm:ss'))"
      } else {
        $taken = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
      }

      $dims = (magick identify -format "%w %h" $thumb) -split " "
      $entries += [pscustomobject]@{
        species = $species
        file    = $n
        taken   = $taken
        w       = [int]$dims[0]
        h       = [int]$dims[1]
      }
    }
}

$json = ConvertTo-Json -InputObject @($entries) -Compress
[System.IO.File]::WriteAllText("$PSScriptRoot/photos.json", $json)
Write-Host "Wrote photos.json with $($entries.Count) photos"
