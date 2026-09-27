raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
%w[mesh_tools live_bevel interactive_tool live_panel].each{|f|load File.expand_path("../src/bevelchamfer/#{f}.rb",__dir__)}
b=BACommunity::BevelChamfer; m=Sketchup.active_model; view=m.active_view; old_camera=view.camera
g=m.entities.add_group;g.name='BC_LIVE_MOUSE'
begin
 f=g.entities.add_face([0,0,0],[100,0,0],[100,100,0],[0,100,0]);f.reverse! if f.normal.z<0;f.pushpull(60)
 g.transformation=Geom::Transformation.translation([5000,0,0]); b::LivePanel.show(g)
 view.camera=Sketchup::Camera.new([5250,-250,200],[5050,50,30],[0,0,1]);view.zoom(g);view.refresh
 t=b::InteractiveTool.new(g)
 screen=view.screen_coords(Geom::Point3d.new(5050,0,50));t.onLButtonDown(0,screen.x.round,screen.y.round,view)
 raise 'Live reference edge failed' unless t.phase==:offset
 screen=view.screen_coords(Geom::Point3d.new(5050,0,55));t.onMouseMove(0,screen.x.round,screen.y.round,view)
 raise 'Live mouse preview missing' if t.instance_variable_get(:@lines).empty?
 t.draw(view);t.onLButtonDown(0,screen.x.round,screen.y.round,view)
 raise 'Live mouse offset failed' unless b::LiveBevel.data(g)['size'].between?(4.5,5.5) && b::LiveBevel.parts(g).last.manifold?
 puts 'PASS Live edge offset picked from result, mouse preview and regenerated solid'
ensure
 b::LivePanel.close;g.erase! if g.valid?;view.camera=old_camera
end
$bc_prefs_before=b::MeshTools.settings
b::PreferencesPanel.show
$bc_prefs_dialog=b::PreferencesPanel.instance_variable_get(:@dialog)
$bc_prefs_dialog.add_action_callback('qa'){|_,json|$bc_prefs_qa=JSON.parse(json)}
puts 'Preferences UI pending ready'
