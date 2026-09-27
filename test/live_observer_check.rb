raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b = BACommunity::BevelChamfer
p, r = b::LiveBevel.parts($bc_observer_group)
raise 'Observer did not regenerate' unless r.manifold? && r.volume > $bc_before && b::Modifier.signature(p) == b::LiveBevel.data($bc_observer_group)['source_signature']
puts "PASS automatic observer after native PushPull: #{r.volume}"
Sketchup.undo
puts 'Undo pending'
