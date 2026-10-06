raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
root = File.expand_path('..', __dir__)
load File.join(root, 'src/bevelchamfer/main.rb')
load File.join(root, 'src/bevelchamfer/live_bevel.rb')
m = Sketchup.active_model
$bc_undo_old_path = m.active_path
$bc_undo_old_selection = m.selection.to_a
$bc_undo_stage = 0
m.active_path = nil if m.active_path
m.start_operation('BC undo regression fixture', true)
$bc_undo_fixture = m.entities.add_group
$bc_undo_fixture.name = 'BC_UNDO_REGRESSION'
$bc_undo_fixture.entities.add_line([0,-20,0], [100,-20,0])
m.commit_operation
# Simulates a model where Live was previously used and its observer remains.
BACommunity::BevelChamfer::LiveBevel.attach(m)
m.active_path = [$bc_undo_fixture]
3.times do |i|
  m.start_operation("BC undo line #{i + 1}", true)
  m.active_entities.add_line([0, i * 20, 0], [100, i * 20, 0])
  m.commit_operation
end
raise 'Undo fixture failed' unless $bc_undo_fixture.entities.grep(Sketchup::Edge).length == 4
puts 'Undo plain group setup complete'
