raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
load File.expand_path('../src/bevelchamfer/interactive_tool.rb',__dir__)
m=Sketchup.active_model; b=BACommunity::BevelChamfer
old_camera=m.active_view.camera; old_path=m.active_path; old_selection=m.selection.to_a
m.active_path=nil if old_path
holder=m.entities.add_group; holder.name='BC_MOUSE_TEST'
begin
 [0,200].each do |x|
  g=holder.entities.add_group
  f=g.entities.add_face([x,0,0],[x+100,0,0],[x+100,100,0],[x,100,0]); f.reverse! if f.normal.z<0; f.pushpull(60); g.explode
 end
 holder.transformation=Geom::Transformation.translation([5000,0,0])
 m.active_path=[holder]; m.selection.clear
 view=m.active_view; view.camera=Sketchup::Camera.new([5300,-400,250],[5150,50,30],[0,0,1]); view.zoom(holder); view.refresh
 t=b::InteractiveTool.new; t.activate
 point=Geom::Point3d.new(5050,0,60); screen=view.screen_coords(point)
 t.onMouseMove(0,screen.x.round,screen.y.round,view)
 t.onLButtonDown(0,screen.x.round,screen.y.round,view)
 raise 'first click selection failed' unless t.edges.length==1
 t.onLButtonDown(0,screen.x.round,screen.y.round,view)
 screen=view.screen_coords(Geom::Point3d.new(5050,0,50))
 t.onMouseMove(0,screen.x.round,screen.y.round,view)
 raise "mouse width incorrect: #{t.size}" unless t.size.between?(9.5,10.5)
 raise 'missing geometric mouse preview' if t.instance_variable_get(:@lines).empty?
 t.draw(view)
 t.onLButtonDown(0,screen.x.round,screen.y.round,view)
 raise 'third click did not create bevel' unless holder.manifold? && t.phase==:selection && holder.entities.grep(Sketchup::Face).length>12
 puts 'PASS real viewport three-click mouse offset, preview draw and solid build'
 before=holder.entities.grep(Sketchup::Face).length
 point=Geom::Point3d.new(5250,0,60); screen=view.screen_coords(point)
 t.onLButtonDoubleClick(0,screen.x.round,screen.y.round,view)
 raise 'double click did not repeat width on next solid' unless holder.manifold? && holder.entities.grep(Sketchup::Face).length>before
 puts 'PASS double click repeats last offset on second loose solid'
ensure
 m.active_path=nil; holder.erase! if holder.valid?
 m.active_path=old_path if old_path&.all?(&:valid?)
 m.active_view.camera=old_camera; m.selection.clear; old_selection.each{|e|m.selection.add(e) if e.valid?}
end
