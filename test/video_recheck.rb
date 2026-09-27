# Repeat-video audit. Runs only in the real SketchUp 2024 Ruby process.
raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
%w[mesh_tools live_bevel interactive_tool live_panel].each { |f| load File.expand_path("../src/bevelchamfer/#{f}.rb", __dir__) }
module BevelVideoRecheck
  B = BACommunity::BevelChamfer
  M = Sketchup.active_model
  def self.check(value, label)
    raise label unless value
    puts "PASS #{label}"
  end
  def self.run
    raise 'Close active context before audit' if M.active_path
    groups = []; selection = M.selection.to_a; preferences = B::MeshTools.settings
    begin
      g = M.entities.add_group; groups << g; g.name = 'BC_VIDEO_RECHECK'
      f = g.entities.add_face([[0,0,0],[100,0,0],[100,100,0],[0,100,0]])
      f.reverse! if f.normal.z < 0; f.pushpull(60)
      edge = g.entities.grep(Sketchup::Edge).first; tool = B::InteractiveTool.new
      edge.soft = true
      check(!tool.eligible?(edge) && !B::LiveBevel.eligible(g.entities).include?(edge), 'Both tools exclude soft edges')
      edge.soft = false; edge.hidden = true
      check(!tool.eligible?(edge) && !B::LiveBevel.eligible(g.entities).include?(edge), 'Both tools exclude hidden edges')
      edge.hidden = false
      g.entities.add_line([0,0,0],[50,0,0])
      check(B::MeshTools.clean(g.entities.grep(Sketchup::Edge)) == 1 && g.manifold?, 'Clean counts removed collinear subdivision')
      B::MeshTools.save(preferences.merge('angle'=>91, 'notifications'=>true, 'language'=>'en'))
      M.active_path = [g]; M.selection.clear
      check(B::MeshTools.auto_soften == 12, 'Auto Soften counts 12 softened box edges')
      notification = B::MeshTools.instance_variable_get(:@notification)
      check(notification.is_a?(UI::Notification) && notification.message.include?('Edges Selected: 12') && notification.message.include?('Edges Softened: 12'), 'Native notification reports separate selection and result counts')
      B::MeshTools.save(preferences.merge('angle'=>0, 'notifications'=>false))
      B::MeshTools.auto_soften
      check(B::MeshTools.instance_variable_get(:@notification).equal?(notification) && g.entities.grep(Sketchup::Edge).none?(&:soft?), 'Disabled notifications and zero-angle hardening')
      M.active_path = nil
      complex = M.entities.add_group; groups << complex; complex.name = 'BC_VIDEO_RECHECK_NOTCH'
      f = complex.entities.add_face([[0,0,0],[30,0,0],[30,20,0],[100,20,0],[100,100,0],[0,100,0]])
      f.reverse! if f.normal.z < 0; f.pushpull(60)
      complex.entities.add_line([0,70,60],[100,70,60])
      complex.entities.grep(Sketchup::Face).find { |face| face.normal.z > 0.9 && face.bounds.center.y > 70 }.pushpull(80)
      B::LiveBevel.create(complex, 5, 4)
      check(B::LiveBevel.parts(complex).all?(&:manifold?), 'Live supports stepped notched shape comparable to 07:03 video')
      $bc_recheck_group = g; $bc_recheck_selection = selection; $bc_recheck_preferences = preferences
      groups.delete(g)
      B::MeshTools.save(preferences)
      B::LivePanel.show(g)
      $bc_recheck_dialog = B::LivePanel.instance_variable_get(:@dialog)
      $bc_recheck_dialog.add_action_callback('qa') { |_, json| $bc_recheck_qa = JSON.parse(json) }
      puts 'Opacity UI ready for native callback'
    ensure
      M.active_path = nil if M.active_path
      B::MeshTools.save(preferences)
      groups.each { |group| group.erase! if group.valid? }
      M.selection.clear; selection.each { |item| M.selection.add(item) if item.valid? }
    end
  end
end
BevelVideoRecheck.run
