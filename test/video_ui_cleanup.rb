raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b = BACommunity::BevelChamfer; m = Sketchup.active_model
p, r = b::LiveBevel.parts($bc_ui_group)
if m.active_path
  raise 'Automatic proxy entry failed' unless m.active_path.last == p && !p.hidden?
  puts 'PASS entering Live group opens panel and editable proxy'
  m.active_path = nil
end
raise 'Live panel did not close on exit' if b::LivePanel.instance_variable_get(:@dialog)
puts 'PASS leaving group closes Live panel'
$bc_ui_group.erase!
m.active_path = $bc_ui_old_path if $bc_ui_old_path&.all?(&:valid?)
m.active_view.camera = $bc_ui_old_camera
m.selection.clear; $bc_ui_old_selection.each { |e| m.selection.add(e) if e.valid? }
