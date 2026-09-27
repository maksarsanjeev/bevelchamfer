# All checks execute in a running SketchUp 2024 through tools/su.ps1.
raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
root = File.expand_path('..', __dir__)
load File.join(root, 'src/bevelchamfer/main.rb')
%w[chamfer mesh_tools live_bevel interactive_tool].each { |f| load File.join(root, "src/bevelchamfer/#{f}.rb") }
module BevelVideoCompletion
  BC = BACommunity::BevelChamfer
  MODEL = Sketchup.active_model
  def self.assert(ok, name)
    raise name unless ok
    puts "PASS #{name}"
  end
  def self.box
    group = MODEL.entities.add_group
    group.name = 'BC_VIDEO_COMPLETION'
    face = group.entities.add_face([0,0,0], [100,0,0], [100,100,0], [0,100,0])
    face.reverse! if face.normal.z < 0
    face.pushpull(60)
    group
  end
  def self.run
    fixtures = []; original = MODEL.selection.to_a; old_path = MODEL.active_path; old_camera = MODEL.active_view.camera
    begin
      MODEL.active_path = nil if old_path
      first = box; fixtures << first
      edge = first.entities.grep(Sketchup::Edge).find { |e| e.start.position.z == 60 && e.end.position.z == 60 }
      halfway = Geom.linear_combination(0.5, edge.start.position, 0.5, edge.end.position)
      split = edge.split(halfway)
      tool = BC::InteractiveTool.new
      path = tool.connected_path(edge)
      assert(path.include?(edge) && path.include?(split) && path.length == 2, 'Alt path follows split edge and stops at branches')
      cylinder = MODEL.entities.add_group; cylinder.name = 'BC_VIDEO_COMPLETION'; fixtures << cylinder
      polygon = 12.times.map { |i| angle = i * 2 * Math::PI / 12; [30 * Math.cos(angle), 30 * Math.sin(angle), 0] }
      cylinder.entities.add_face(polygon).pushpull(40)
      rim = cylinder.entities.grep(Sketchup::Edge).find { |e| e.vertices.all? { |v| v.position.z.abs == 40 } }
      assert(tool.connected_path(rim).length == 12, 'Alt path follows curved rim through branched vertices')
      MODEL.selection.clear
      tool.activate
      tool.onUserText('12', MODEL.active_view)
      assert(tool.segments == 12 && tool.edges.empty?, 'Idle Measurements changes segment count')
      preview_box = box; fixtures << preview_box
      MODEL.selection.add(preview_box)
      tool = BC::InteractiveTool.new; tool.activate
      assert(!tool.edges.empty? && !tool.instance_variable_get(:@lines).any?, 'Selected source is ready before hover')
      tool.update_preview
      assert(!tool.instance_variable_get(:@lines).empty?, 'Preview computes before offset reference point')
      tool.onUserText('8mm; 6', MODEL.active_view)
      assert(preview_box.manifold? && tool.segments == 6 && (tool.size - 8.mm).abs < 1.0e-6, 'Measurements accepts precise offset and segments')
      second = box; fixtures << second
      targets = second.entities.grep(Sketchup::Edge).select { |e| e.faces.length == 2 }
      BC::Chamfer.apply(targets, 10, 5, mode: :offset)
      second.entities.grep(Sketchup::Face).each { |face| face.delete_attribute('BACommunity_BevelSurface', 'generated') }
      edges = second.entities.grep(Sketchup::Edge)
      borders = edges.select { |e| BC::MeshTools.border?(e) }
      assert(!borders.empty?, 'Imported bevel borders inferred without extension attributes')
      BC::MeshTools.soften(edges, {'angle' => 40, 'smooth' => true, 'borders' => false})
      eligible_borders = borders.select(&:soft?)
      assert(!eligible_borders.empty? && eligible_borders.none?(&:smooth?), 'Imported borders remain hard-shaded when disabled')
      BC::MeshTools.soften(edges, {'angle' => 40, 'smooth' => true, 'borders' => true})
      assert(eligible_borders.all?(&:smooth?), 'Imported borders smooth when enabled')
      # Real InputPoint/PickHelper/viewport path, guide drawing, and cursor.
      MODEL.active_path = nil if MODEL.active_path
      first.transformation = Geom::Transformation.translation([5000, 0, 0])
      MODEL.active_path = [first]; MODEL.selection.clear
      view = MODEL.active_view
      view.camera = Sketchup::Camera.new([5300,-400,250], [5050,50,30], [0,0,1])
      view.zoom(first); view.refresh
      picked = first.entities.grep(Sketchup::Edge).find do |e|
        e.start.position.z == 60 && e.end.position.z == 60 && e.length > 40
      end
      mid = Geom.linear_combination(0.5, picked.start.position, 0.5, picked.end.position)
      screen = view.screen_coords(mid)
      tool = BC::InteractiveTool.new
      MODEL.select_tool(tool)
      tool.onMouseMove(ALT_MODIFIER_MASK, screen.x.round, screen.y.round, view)
      tool.onLButtonDown(ALT_MODIFIER_MASK, screen.x.round, screen.y.round, view)
      assert(tool.edges.length == 2 && !tool.instance_variable_get(:@lines).empty?, 'Alt mouse picks path and previews before reference click')
      tool.onLButtonDown(0, screen.x.round, screen.y.round, view)
      assert(tool.phase == :offset && tool.instance_variable_get(:@reference_point), 'Reference marker fixed on edge')
      tool.onMouseMove(0, screen.x.round, screen.y.round - 15, view)
      tool.draw(view)
      assert(tool.onSetCursor && BC::InteractiveTool.cursor_id, 'Custom cursor and dotted guide draw in SketchUp viewport')
      MODEL.select_tool(nil)
      puts 'VIDEO COMPLETION PASS'
    ensure
      MODEL.active_path = nil if MODEL.active_path
      MODEL.select_tool(nil)
      MODEL.selection.clear
      fixtures.each { |group| group.erase! if group.valid? }
      MODEL.active_path = old_path if old_path&.all?(&:valid?)
      MODEL.active_view.camera = old_camera
      original.each { |entity| MODEL.selection.add(entity) if entity.valid? }
    end
  end
end
BevelVideoCompletion.run
