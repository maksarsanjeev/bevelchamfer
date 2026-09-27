# Copyright 2026 B&A community. Apache-2.0.
# Every assertion and UI callback executes in real SketchUp 2024.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Start-Transcript -Path (Join-Path $root 'build/su2024-checks.log') -Force | Out-Null
$files = @(
 'regression', 'integration', 'holes', 'video_features', 'video_safety', 'interactive_mouse',
 'live_observer', 'live_observer_check', 'live_observer_undo', 'live_observer_redo',
 'live_edit_context', 'live_edit_context_pushpull', 'live_edit_context_check',
 'video_ui', 'video_ui_check', 'video_ui_finish', 'video_ui_cleanup',
 'live_mouse', 'preferences_ui', 'preferences_ui_check'
)
try {
    foreach ($file in $files) {
        & (Join-Path $PSScriptRoot 'su.ps1') -File (Join-Path $root "test/$file.rb")
    }
    Write-Host 'ALL LIVE SKETCHUP 2024 CHECKS PASSED'
} finally {
    Stop-Transcript | Out-Null
}
