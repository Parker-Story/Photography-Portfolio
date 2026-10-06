# Windows PowerShell version of resize.sh
# Reads originals/, writes photos/full + photos/thumb, regenerates photos.json.
# Skips photos that already have output. Delete a photo's files in
# photos/full and photos/thumb to regenerate it.
# Requires ImageMagick 7 (`magick` on PATH).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

New-Item -ItemType Directory -Force photos/full, photos/thumb | Out-Null

$entries = @()
Get-ChildItem originals -File |
  Where-Object { $_.Extension -match '^\.(jpe?g|png)$' } |
  Sort-Object Name |
  ForEach-Object {
    $n = $_.BaseName + ".jpg"
    $full = "photos/full/$n"
    $thumb = "photos/thumb/$n"

    if (-not (Test-Path $full)) {
      Write-Host "Processing $n"
      magick $_.FullName -auto-orient -resize "1600x1600>" -colorspace sRGB -quality 82 $full
      magick $_.FullName -auto-orient -resize "600x600>" -colorspace sRGB -quality 80 $thumb
    }

    $dims = (magick identify -format "%w %h" $thumb) -split " "
    $entries += [pscustomobject]@{ file = $n; w = [int]$dims[0]; h = [int]$dims[1] }
  }

$json = ConvertTo-Json -InputObject @($entries) -Compress
[System.IO.File]::WriteAllText("$PSScriptRoot/photos.json", $json)
Write-Host "Wrote photos.json with $($entries.Count) photos"