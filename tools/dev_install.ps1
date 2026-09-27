# Copyright 2026 B&A community. Licensed under Apache License 2.0.
# Установка исходников только в SketchUp 2024, без публикации RBZ.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$plugins = Join-Path $env:APPDATA 'SketchUp\SketchUp 2024\SketchUp\Plugins'
if (-not (Test-Path -LiteralPath $plugins)) { throw 'Не найдена папка Plugins SketchUp 2024.' }
$entry = Join-Path $plugins 'bevelchamfer.rb'
$folder = Join-Path $plugins 'bevelchamfer'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root "build\installed-backup-$stamp"
if ((Test-Path -LiteralPath $entry) -or (Test-Path -LiteralPath $folder)) {
    New-Item -ItemType Directory -Force $backup | Out-Null
    if (Test-Path -LiteralPath $entry) { Copy-Item -LiteralPath $entry -Destination $backup }
    if (Test-Path -LiteralPath $folder) { Copy-Item -LiteralPath $folder -Destination $backup -Recurse }
}
Copy-Item -LiteralPath (Join-Path $root 'src\bevelchamfer.rb') -Destination $entry -Force
New-Item -ItemType Directory -Force $folder | Out-Null
Get-ChildItem -LiteralPath (Join-Path $root 'src\bevelchamfer') | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $folder -Recurse -Force
}
Write-Host "Исходники установлены в $plugins. При следующем запуске SketchUp 2024 расширение загрузится автоматически."
