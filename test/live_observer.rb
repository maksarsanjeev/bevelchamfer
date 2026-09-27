raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
%w[chamfer mesh_tools live_bevel interactive_tool live_panel].each { |f| load File.expand_path("../src/bevelchamfer/#{f}.rb", __dir__) }
m = Sketchup.active_model
m.start_operation('BC observer test fixture', true)
$bc_observer_group = m.entities.add_group
$bc_observer_group.name = 'BC_OBSERVER_TEST'
f = $bc_observer_group.entities.add_face([0,0,0],[100,0,0],[100,100,0],[0,100,0]); f.reverse! if f.normal.z < 0; f.pushpull(60)
m.commit_operation
b = BACommunity::BevelChamfer
b::LiveBevel.create($bc_observer_group, 5, 4)
p, r = b::LiveBevel.parts($bc_observer_group)
$bc_before = r.volume
m.start_operation('BC native PushPull observer', true)
p.entities.grep(Sketchup::Face).find { |f| f.normal.z > 0.9 }.pushpull(20)
m.commit_operation
puts 'Observer pending: native PushPull committed; no explicit sync called.'
