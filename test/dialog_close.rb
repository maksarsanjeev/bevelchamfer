# Native windows and preview tool, executed exclusively in SketchUp 2024.
raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
load File.expand_path('../src/bevelchamfer/chamfer_panel.rb', __dir__)
unless defined?(BA::Insolyanka::Panel)
  module BA; module Insolyanka; VERSION = '0.2.0'; end; end
  root = ENV['BC_INSOLYANKA_ROOT'] || File.expand_path('../../insolyanka', __dir__)
  load File.join(root, 'insolyanka/main.rb')
end
$bc_close_audit = {cycle: 0, passes: 0, done: false, error: nil}
b = BACommunity::BevelChamfer
selection = Sketchup.active_model.selection.to_a
entities_before = Sketchup.active_model.entities.to_a
next_cycle = nil
next_cycle = lambda do
  begin
    b::ChamferPanel.show
    BA::Insolyanka::Panel.show
    bevel = b::ChamferPanel.instance_variable_get(:@dialog)
    insol = BA::Insolyanka::Panel.instance_variable_get(:@dialog)
    original_script = bevel.method(:execute_script)
    bevel.define_singleton_method(:execute_script) do |code|
      raise 'JavaScript sent to a closed window' unless visible?
      original_script.call(code)
    end
    b::ChamferPreview.show([[Geom::Point3d.new(0,0,0), Geom::Point3d.new(10,0,0)]])
    UI.start_timer(0.7, false) do
      begin
        if $bc_close_audit[:cycle].even? then bevel.close; insol.close
        else insol.close; bevel.close end
        b::ChamferPanel.push
        b::ChamferPanel.preview_state(false)
        UI.start_timer(0.3, false) do
          begin
            raise 'Closed dialog reference retained as current' unless b::ChamferPanel.instance_variable_get(:@dialog).nil?
            raise 'Preview stayed active after closure' if b::ChamferPreview.instance_variable_get(:@current)&.active?
            raise 'Unexpected model mutation' unless Sketchup.active_model.entities.to_a == entities_before
            $bc_close_audit[:passes] += 1
            $bc_close_audit[:cycle] += 1
            GC.start
            if $bc_close_audit[:cycle] < 6
              next_cycle.call
            else
              Sketchup.active_model.selection.clear
              selection.each { |entity| Sketchup.active_model.selection.add(entity) if entity.valid? }
              $bc_close_audit[:done] = true
            end
          rescue StandardError => error
            $bc_close_audit[:error] = error.message; $bc_close_audit[:done] = true
          end
        end
      rescue StandardError => error
        $bc_close_audit[:error] = error.message; $bc_close_audit[:done] = true
      end
    end
  rescue StandardError => error
    $bc_close_audit[:error] = error.message; $bc_close_audit[:done] = true
  end
end
next_cycle.call
puts 'Native paired-window close checks started'
