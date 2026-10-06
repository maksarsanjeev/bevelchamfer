raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
root = File.expand_path('..', __dir__)
load File.join(root, 'src/bevelchamfer/main.rb')
load File.join(root, 'src/bevelchamfer/live_bevel.rb')
m = Sketchup.active_model
m.active_path = nil if m.active_path
$bc_undo_background_live = m.entities.add_group
$bc_undo_background_live.name = 'BC_UNDO_BACKGROUND_LIVE'
face = $bc_undo_background_live.entities.add_face([0,0,0], [100,0,0], [100,100,0], [0,100,0])
face.reverse! if face.normal.z < 0
face.pushpull(60)
BACommunity::BevelChamfer::LiveBevel.create($bc_undo_background_live, 5, 4)
load File.join(__dir__, 'undo_plain_group_setup.rb')
puts 'Undo setup with unrelated Live object complete'
