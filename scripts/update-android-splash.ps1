param(
  [string]$Source = "assets/images/logo.png",
  [string]$ResRoot = "android/app/src/main/res"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Source)) {
  throw "Source file not found: $Source"
}

try {
  Add-Type -AssemblyName System.Drawing
} catch {
  throw "Не удалось загрузить System.Drawing. Запустите под Windows PowerShell / Windows."
}

$sizes = [ordered]@{
  "mdpi"   = 256
  "hdpi"   = 384
  "xhdpi"  = 512
  "xxhdpi" = 768
  "xxxhdpi"= 1024
}

function Ensure-Dir([string]$path) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
}

function Resize-Png([System.Drawing.Image]$src, [int]$size, [string]$outPath) {
  Ensure-Dir $outPath
  # Более совместимо: не указываем PixelFormat явно (на некоторых окружениях New-Object плохо резолвит enum)
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($src, 0, 0, $size, $size)
  } finally {
    $g.Dispose()
  }

  try {
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $bmp.Dispose()
  }
}

$srcImg = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
try {
  foreach ($density in $sizes.Keys) {
    $size = [int]$sizes[$density]

    $targets = @(
      (Join-Path $ResRoot "drawable-$density/splash.png"),
      (Join-Path $ResRoot "drawable-$density/android12splash.png"),
      (Join-Path $ResRoot "drawable-night-$density/android12splash.png")
    )

    foreach ($t in $targets) {
      Resize-Png -src $srcImg -size $size -outPath $t
    }
  }
} finally {
  $srcImg.Dispose()
}

Write-Host "OK: Android splash обновлён из $Source" -ForegroundColor Green


