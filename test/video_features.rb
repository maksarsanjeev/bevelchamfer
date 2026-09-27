# Run only through tools/su.ps1 in real SketchUp 2024.
raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
bc_root = File.expand_path('..', __dir__)
load File.join(bc_root, 'src/bevelchamfer/main.rb')
%w[chamfer mesh_tools live_bevel interactive_tool live_panel].each { |f| load "#{bc_root}/src/bevelchamfer/#{f}.rb" }
module BevelVideoTest
  M = BACommunity::BevelChamfer
  MODEL = Sketchup.active_model
  def self.assert(condition, message)
    raise message unless condition
    puts "PASS #{message}"
  end
  def self.box
    g = MODEL.entities.add_group; g.name = 'BC_VIDEO_TEST'
    f = g.entities.add_face([0,0,0],[100,0,0],[100,100,0],[0,100,0]); f.reverse! if f.normal.z < 0; f.pushpull(60)
    g
  end
  def self.run
    groups = []; previous = MODEL.selection.to_a
    begin
      g = box; groups << g
      M::LiveBevel.create(g, 10, 4)
      proxy, result = M::LiveBevel.parts(g)
      assert(proxy.manifold? && proxy.entities.grep(Sketchup::Face).length == 6 && result.manifold? && result.locked?, 'Live original and locked solid result')
      assert(result.entities.grep(Sketchup::Face).length == 182, 'Live segments and offset')
      original_volume = result.volume
      MODEL.start_operation('Native PushPull', true)
      proxy.entities.grep(Sketchup::Face).find { |f| f.normal.z > 0.9 }.pushpull(20)
      MODEL.commit_operation
      M::LiveBevel.sync
      assert(result.manifold? && result.volume > original_volume && !g.get_attribute(M::LiveBevel::KEY, 'error'), 'PushPull regenerates Live result')
      M::LiveBevel.update(g, {'display' => 'proxy'})
      assert(!proxy.hidden? && result.hidden?, 'Proxy display')
      M::LiveBevel.update(g, {'display' => 'bevel', 'opacity' => 0.5, 'borders' => false})
      assert(proxy.hidden? && !result.hidden? && result.entities.grep(Sketchup::Face).all? { |f| (f.material.alpha - 0.5).abs < 0.01 }, 'Bevel display and transparency')
      borders = result.entities.grep(Sketchup::Edge).select { |e| M::MeshTools.border?(e) }
      assert(!borders.empty? && borders.none?(&:smooth?), 'Bevel border smoothing switch')
      old_hash = M::Modifier.signature(result)
      begin; M::LiveBevel.update(g, {'size' => 500}); rescue M::Chamfer::Error; end
      assert(M::Modifier.signature(result) == old_hash && M::LiveBevel.data(g)['size'] == 10, 'Invalid Live width rolls back')
      M::LiveBevel.finish(g, false)
      assert(!M::LiveBevel.data(g) && g.manifold? && (g.volume - 800000).abs < 0.01, 'Remove Live retains edited original')
      M::LiveBevel.create(g, 8, 6); M::LiveBevel.finish(g, true)
      assert(g.manifold? && !M::LiveBevel.data(g) && g.entities.grep(Sketchup::Group).empty?, 'Commit removes proxy and bakes solid')
      # Actual line subdivision + PushPull: the topology-changing edit in video.
      g2 = box; groups << g2; M::LiveBevel.create(g2, 5, 4)
      p2, r2 = M::LiveBevel.parts(g2)
      MODEL.start_operation('Line and PushPull', true)
      p2.entities.add_line([0,0,30],[100,0,30])
      front = p2.entities.grep(Sketchup::Face).find { |f| f.normal.y < -0.9 && f.bounds.center.z < 30 }
      front.pushpull(40)
      MODEL.commit_operation; M::LiveBevel.sync
      assert(r2.manifold? && !g2.get_attribute(M::LiveBevel::KEY, 'error') && r2.volume > 600000, 'New edge and PushPull topology regenerate Live')
      # Soften is angle based, not merely hiding every edge.
      edges = g.entities.grep(Sketchup::Edge)
      M::MeshTools.soften(edges, {'angle'=>1,'smooth'=>true,'borders'=>true})
      hard = edges.count { |e| !e.soft? }
      M::MeshTools.soften(edges, {'angle'=>30,'smooth'=>true,'borders'=>false})
      assert(edges.count { |e| !e.soft? } < hard && edges.any?(&:soft?), 'Auto soften respects angle')
      M::MeshTools.soften(edges, {'angle'=>0,'smooth'=>true,'borders'=>true})
      assert(edges.none?(&:soft?) && edges.none?(&:smooth?), 'Angle zero hardens all edges')
      clean = box; groups << clean
      e = clean.entities.add_line([0,0,60],[100,100,60])
      assert(M::MeshTools.clean([e]) == 1 && clean.manifold? && clean.entities.grep(Sketchup::Face).length == 6, 'Clean removes coplanar edge without damaging solid')
      interactive = box; groups << interactive; MODEL.selection.clear; MODEL.selection.add(interactive)
      tool = M::InteractiveTool.new; tool.activate
      selected = tool.edges.dup; tool.choose(selected.take(1), COPY_MODIFIER_MASK | CONSTRAIN_MODIFIER_MASK)
      assert(tool.edges.length == 11, 'Ctrl Shift subtract selection')
      tool.choose(selected.take(1), COPY_MODIFIER_MASK)
      assert(tool.edges.length == 12, 'Ctrl adds selection')
      tool.instance_variable_set(:@size, 10); tool.apply_current
      before = interactive.entities.grep(Sketchup::Face).length
      tool.onKeyDown(VK_UP, 1, 0, MODEL.active_view)
      assert(interactive.manifold? && interactive.entities.grep(Sketchup::Face).length > before, 'Arrow regenerates last bevel from session source')
      tool.onUserText('8mm', MODEL.active_view)
      assert(interactive.manifold? && (tool.size - 8.mm).abs < 1.0e-6, 'Measurements box applies exact width')
      puts 'VIDEO FEATURES PASS'
    ensure
      MODEL.active_path = nil if MODEL.active_path
      M::LivePanel.close; MODEL.selection.clear
      groups.each { |g| g.erase! if g.valid? }
      previous.each { |e| MODEL.selection.add(e) if e.valid? }
    end
  end
end
BevelVideoTest.run
