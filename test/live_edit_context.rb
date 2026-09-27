raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
%w[chamfer mesh_tools live_bevel interactive_tool live_panel].each { |f| load File.expand_path("../src/bevelchamfer/#{f}.rb", __dir__) }
m=Sketchup.active_model; b=BACommunity::BevelChamfer
$bc_context_old_camera=m.active_view.camera
$bc_context_group=m.entities.add_group; $bc_context_group.name='BC_EDIT_CONTEXT'
f=$bc_context_group.entities.add_face([0,0,0],[100,0,0],[100,100,0],[0,100,0]); f.reverse! if f.normal.z<0; f.pushpull(60)
$bc_context_group.transformation=Geom::Transformation.translation([5000,1000,0])
b::LiveBevel.create($bc_context_group,5,4)
p,r=b::LiveBevel.parts($bc_context_group)
$bc_context_volume=r.volume
m.active_path=[$bc_context_group,p]
puts 'Open translated proxy context pending'
