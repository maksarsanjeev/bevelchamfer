raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
%w[chamfer modifier mesh_tools live_bevel interactive_tool live_panel].each { |f| load File.expand_path("../src/bevelchamfer/#{f}.rb", __dir__) }
module BevelVideoSafety
 M=BACommunity::BevelChamfer; MODEL=Sketchup.active_model
 def self.check(value,label); raise label unless value; puts "PASS #{label}"; end
 def self.box(parent=MODEL.entities)
  g=parent.add_group; g.name='BC_VIDEO_SAFETY'; f=g.entities.add_face([0,0,0],[100,0,0],[100,100,0],[0,100,0]); f.reverse! if f.normal.z<0; f.pushpull(60); g
 end
 def self.run
  groups=[]; selection=MODEL.selection.to_a
  begin
   g=box; groups<<g
   split=g.entities.add_line([0,0,0],[50,0,0])
   check(g.entities.grep(Sketchup::Edge).length==13,'fixture has divided straight edge')
   M::MeshTools.clean(g.entities.grep(Sketchup::Edge))
   check(g.manifold? && g.entities.grep(Sketchup::Edge).length==12,'Clean joins redundant collinear divisions')
   diagonal=g.entities.add_line([0,0,60],[100,100,60]); diagonal.faces.first.material=MODEL.materials.add('BC_CLEAN_DIFFERENT')
   M::MeshTools.clean([diagonal]); check(diagonal.valid?,'Clean retains material boundary')
   g2=box; groups<<g2; M::LiveBevel.create(g2,10,4)
   p,r=M::LiveBevel.parts(g2); before=M::Modifier.signature(r)
   MODEL.start_operation('Invalid source edit fixture',true)
   p.entities.grep(Sketchup::Face).find{|f|f.normal.z>0.9}.pushpull(-55); MODEL.commit_operation
   M::LiveBevel.sync
   check((p.volume-50000).abs<0.01 && M::Modifier.signature(r)==before && !!g2.get_attribute(M::LiveBevel::KEY,'error'),'Invalid source edit retained with last valid result')
   M::LiveBevel.finish(g2,false); check(g2.manifold? && (g2.volume-50000).abs<0.01,'Remove after failure returns edited source')
   g3=box; groups<<g3; M::LiveBevel.create(g3,10,4)
   sibling=MODEL.entities.add_instance(g3.definition,Geom::Transformation.translation([200,0,0])); groups<<sibling
   sibling.set_attribute(M::LiveBevel::KEY,'data',g3.get_attribute(M::LiveBevel::KEY,'data'))
   original=M::Modifier.signature(M::LiveBevel.parts(sibling).last)
   M::LiveBevel.update(g3,{'size'=>5,'opacity'=>0.4})
   check(M::Modifier.signature(M::LiveBevel.parts(sibling).last)==original && M::LiveBevel.data(sibling)['size']==10,'Live parameter update isolates copied component')
   # SKP round trip for live proxy, result and parameters.
   wrapper=MODEL.entities.add_group; groups<<wrapper
   stored=wrapper.entities.add_instance(g3.definition,Geom::Transformation.new)
   stored.set_attribute(M::LiveBevel::KEY,'data',g3.get_attribute(M::LiveBevel::KEY,'data'))
   path=File.expand_path('../build/live-roundtrip.skp',__dir__)
   wrapper.definition.save_as(path)
   loaded=MODEL.entities.add_instance(MODEL.definitions.load(path),Geom::Transformation.translation([0,200,0])); groups<<loaded
   child=loaded.definition.entities.find { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
   M::LiveBevel.update(child,{'size'=>7,'opacity'=>1.0})
   check(M::LiveBevel.parts(child).last.manifold? && M::LiveBevel.data(child)['size']==7,'Live editable after SKP serialization')
   loose_holder=MODEL.entities.add_group; groups<<loose_holder
   loose=box(loose_holder.entities); loose.explode
   unrelated=loose_holder.entities.add_group; unrelated.entities.add_line([300,0,0],[350,0,0])
   MODEL.active_path=[loose_holder]; MODEL.selection.clear; MODEL.selection.add(loose_holder.entities.grep(Sketchup::Edge).first)
   tool=M::InteractiveTool.new; tool.activate; tool.instance_variable_set(:@size,10); tool.apply_current
   tool.onKeyDown(VK_DOWN,1,0,MODEL.active_view)
   check(unrelated.valid? && unrelated.entities.length==1,'Interactive repeat preserves unrelated nested objects')
   puts 'VIDEO SAFETY PASS'
  ensure
   MODEL.active_path=nil; M::LivePanel.close; MODEL.selection.clear
   groups.each{|g|g.erase! if g.valid?}; selection.each{|e|MODEL.selection.add(e) if e.valid?}
  end
 end
end
BevelVideoSafety.run
