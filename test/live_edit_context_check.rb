raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b=BACommunity::BevelChamfer; m=Sketchup.active_model; p,r=b::LiveBevel.parts($bc_context_group)
raise 'Edit context not retained' unless m.active_path.last==p
raise 'Edit context rebuild failed' unless r.manifold? && r.volume>$bc_context_volume && !$bc_context_group.get_attribute(b::LiveBevel::KEY,'error')
raise 'Edit context shifted result' unless $bc_context_group.bounds.width<101 && $bc_context_group.bounds.depth<101
puts 'PASS native PushPull inside translated proxy automatically rebuilds without moving result'
b::LiveBevel.update($bc_context_group,{'size'=>7,'segments'=>6})
raise 'Parameter update lost edit context' unless m.active_path&.last==p
raise 'Parameter update shifted result' unless $bc_context_group.bounds.width<101 && r.manifold?
puts 'PASS Live parameters while editing retain proxy context and result position'
m.active_path=nil; b::LivePanel.close; $bc_context_group.erase!; m.active_view.camera=$bc_context_old_camera
