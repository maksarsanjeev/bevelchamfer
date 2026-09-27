raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b = BACommunity::BevelChamfer
begin
  raise 'Reopened Apply callback failed' unless $bc_reopen_group.manifold? && $bc_reopen_group.entities.grep(Sketchup::Face).length > 6 && b::Modifier.data($bc_reopen_group)
  puts 'PASS native Apply button after reopen builds solid with saved parameters'
ensure
  $bc_reopen_dialog.close
  $bc_reopen_group.erase! if $bc_reopen_group.valid?
  m = Sketchup.active_model; m.selection.clear
  $bc_reopen_selection.each { |entity| m.selection.add(entity) if entity.valid? }
end
