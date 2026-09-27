raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
$bc_reopen_dialog.execute_script("document.getElementById('preview').click();")
