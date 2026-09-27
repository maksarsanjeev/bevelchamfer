raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b = BACommunity::BevelChamfer
p, r = b::LiveBevel.parts($bc_observer_group)
raise 'Redo failed' unless (p.volume-800000).abs < 0.01 && r.volume > $bc_before
puts 'PASS Redo restores PushPull and Live result together'
$bc_observer_group.erase!
