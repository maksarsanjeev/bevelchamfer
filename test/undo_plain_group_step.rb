raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
m = Sketchup.active_model
begin
  expected = 4 - $bc_undo_stage
  raise "Undo chain stopped: expected #{expected} edges" unless $bc_undo_fixture&.valid? && $bc_undo_fixture.entities.grep(Sketchup::Edge).length == expected
  raise 'Undo left the group' unless m.active_path == [$bc_undo_fixture]
  Sketchup.send_action('editUndo:')
  $bc_undo_stage += 1
  puts "Undo #{ $bc_undo_stage } sent"
rescue StandardError
  m.active_path = nil if m.active_path
  $bc_undo_fixture.erase! if $bc_undo_fixture&.valid?
  m.active_path = $bc_undo_old_path if $bc_undo_old_path&.all?(&:valid?)
  raise
end
