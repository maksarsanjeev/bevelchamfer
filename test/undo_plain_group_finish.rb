raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
m = Sketchup.active_model
begin
  raise 'Three Undo calls did not remove three lines' unless $bc_undo_fixture&.valid? && $bc_undo_fixture.entities.grep(Sketchup::Edge).length == 1
  raise 'Undo left the group' unless m.active_path == [$bc_undo_fixture]
  puts 'PASS three consecutive Undo calls inside ordinary group with Live observer attached'
ensure
  m.active_path = nil if m.active_path
  $bc_undo_fixture.erase! if $bc_undo_fixture&.valid?
  m.active_path = $bc_undo_old_path if $bc_undo_old_path&.all?(&:valid?)
  m.selection.clear
  ($bc_undo_old_selection || []).each { |e| m.selection.add(e) if e.valid? }
end
