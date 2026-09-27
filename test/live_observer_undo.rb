raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b = BACommunity::BevelChamfer
p, r = b::LiveBevel.parts($bc_observer_group)
raise 'Undo failed' unless (p.volume-600000).abs < 0.01 && (r.volume-$bc_before).abs < 0.01
puts 'PASS Undo reverses original PushPull and Live result together'
Sketchup.send_action('editRedo:')
puts 'Redo pending'
