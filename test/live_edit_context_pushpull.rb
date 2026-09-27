raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
m=Sketchup.active_model; p,r=BACommunity::BevelChamfer::LiveBevel.parts($bc_context_group)
m.start_operation('Native PushPull inside proxy',true)
p.entities.grep(Sketchup::Face).find { |f| f.normal.z>0.9 }.pushpull(20)
m.commit_operation
puts 'Native PushPull in active translated proxy committed; no sync'
