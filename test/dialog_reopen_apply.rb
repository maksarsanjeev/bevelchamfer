raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b = BACommunity::BevelChamfer
raise 'Reopened preview callback failed' unless b::ChamferPreview.instance_variable_get(:@current)&.active? && $bc_reopen_group.entities.grep(Sketchup::Face).length == 6
puts 'PASS native Show button after reopen leaves source intact'
$bc_reopen_dialog.execute_script("document.getElementById('apply').click();")
