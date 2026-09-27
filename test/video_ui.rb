raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
%w[chamfer mesh_tools live_bevel interactive_tool live_panel].each { |f| load File.expand_path("../src/bevelchamfer/#{f}.rb", __dir__) }
b = BACommunity::BevelChamfer; m = Sketchup.active_model
$bc_ui_old_path = m.active_path unless defined?($bc_ui_old_path); $bc_ui_old_camera ||= m.active_view.camera; $bc_ui_old_selection ||= m.selection.to_a
m.active_path = nil if m.active_path
m.entities.grep(Sketchup::Group).select { |g| g.name == 'BC_VIDEO_UI' }.each(&:erase!)
$bc_ui_group = m.entities.add_group; $bc_ui_group.name = 'BC_VIDEO_UI'
f = $bc_ui_group.entities.add_face([0,0,0],[100,0,0],[100,100,0],[0,100,0]); f.reverse! if f.normal.z < 0; f.pushpull(60)
$bc_ui_group.transformation = Geom::Transformation.translation([100000,0,0])
m.active_view.camera = Sketchup::Camera.new([100250,-250,200],[100050,50,30],[0,0,1])
m.active_path = [$bc_ui_group]; m.selection.clear
m.active_view.camera = Sketchup::Camera.new([100250,-250,200],[100050,50,30],[0,0,1])
m.active_view.zoom($bc_ui_group)
t = b::InteractiveTool.new; t.activate; view = m.active_view
view.refresh
vertices = $bc_ui_group.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
found_vertex = vertices.any? do |v|
  screen = view.screen_coords(v.position)
  t.onMouseMove(0, screen.x.round, screen.y.round, view)
  t.instance_variable_get(:@hover).length == 3
end
raise 'Vertex picking failed' unless found_vertex
puts 'PASS real viewport vertex picking selects 3 edges'
found_face = $bc_ui_group.entities.grep(Sketchup::Face).any? do |face|
  screen = view.screen_coords(face.bounds.center)
  t.onMouseMove(0, screen.x.round, screen.y.round, view)
  t.instance_variable_get(:@hover).length == 4
end
raise 'Face picking failed' unless found_face
puts 'PASS real viewport face picking selects 4 perimeter edges'
found_edge = $bc_ui_group.entities.grep(Sketchup::Edge).find do |e|
  screen = view.screen_coords(Geom.linear_combination(0.5,e.start.position,0.5,e.end.position))
  t.onMouseMove(0, screen.x.round, screen.y.round, view)
  t.instance_variable_get(:@hover).length == 1
end
raise 'Edge picking failed' unless found_edge
puts 'PASS real viewport single edge picking'
screen = view.screen_coords(Geom.linear_combination(0.5,found_edge.start.position,0.5,found_edge.end.position))
t.onLButtonDown(0,screen.x.round,screen.y.round,view)
raise 'first click' unless t.edges.length == 1 && t.phase == :selection
t.onLButtonDown(0,screen.x.round,screen.y.round,view)
raise 'second click' unless t.phase == :offset
t.onCancel(0,view)
raise 'Escape did not return to selection' unless t.phase == :selection && t.edges.length == 1
puts 'PASS three-click tool selection/reference and Escape'
m.active_path = nil
b::LivePanel.show($bc_ui_group)
$bc_live_dialog = b::LivePanel.instance_variable_get(:@dialog)
$bc_live_dialog.add_action_callback('qa') { |_, json| $bc_live_ui = JSON.parse(json); puts "LIVE UI #{json}" }
puts 'Live dialog pending ready'
