raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
raise 'Close-cycle test incomplete' unless $bc_close_audit && $bc_close_audit[:done] && !$bc_close_audit[:error] && $bc_close_audit[:passes] == 6
puts 'PASS six native paired-window close cycles with preview and GC'
m = Sketchup.active_model
$bc_reopen_selection = m.selection.to_a
$bc_reopen_group = m.entities.add_group
$bc_reopen_group.name = 'BC_DIALOG_REOPEN'
f = $bc_reopen_group.entities.add_face([[0,0,0],[1000.mm,0,0],[1000.mm,700.mm,0],[0,700.mm,0]])
f.reverse! if f.normal.z < 0; f.pushpull(400.mm)
m.selection.clear; m.selection.add($bc_reopen_group)
BACommunity::BevelChamfer::ChamferPanel.show
$bc_reopen_dialog = BACommunity::BevelChamfer::ChamferPanel.instance_variable_get(:@dialog)
puts 'Reopened compact native dialog ready for buttons'
