# Гоняет ruby-файл в живом SketchUp через мост sketchup-mcp (localhost:8080).
# Copyright 2026 B&A community. Licensed under Apache License 2.0.
# Ruby-файл загружается по пути, чтобы __dir__ определялся корректно.
param([Parameter(Mandatory = $true)][string]$File)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$rubyPath = (Resolve-Path -LiteralPath $File).Path.Replace('\', '/').Replace("'", "\'")
$code = "raise 'Tests require SketchUp 2024' unless Sketchup.version.to_i == 24; load '$rubyPath'"
$body = @{ code = $code } | ConvertTo-Json -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$response = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8080/ruby/execute' -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 180
$response.RawContentStream.Position = 0
$reader = New-Object System.IO.StreamReader($response.RawContentStream, [System.Text.Encoding]::UTF8)
$r = $reader.ReadToEnd() | ConvertFrom-Json
$reader.Dispose()
if ($r.output) { $r.output | ForEach-Object { Write-Host $_ } }
if ($r.error) { throw ($r.error + ' ' + ($r.backtrace -join "`n")) }
if ($null -ne $r.result) { Write-Host "=> $($r.result)" }
