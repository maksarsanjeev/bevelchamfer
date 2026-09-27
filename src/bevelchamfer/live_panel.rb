# Copyright 2026 B&A community. Licensed under Apache-2.0.
require 'json'
module BACommunity
  module BevelChamfer
    module LivePanel
      module_function
      def show(object = nil)
        unless object
          selected = Sketchup.active_model.selection.to_a
          object = selected.first if selected.length == 1 && (selected.first.is_a?(Sketchup::Group) || selected.first.is_a?(Sketchup::ComponentInstance))
        end
        raise Chamfer::Error, 'Выделите одну группу или компонент.' unless object
        @object = object
        LiveBevel.create(object, 20.mm / world_scale) unless LiveBevel.data(object)
        unless @dialog
          @dialog = UI::HtmlDialog.new(dialog_title: 'bevelchamfer — Live', preferences_key: 'BACommunity_BevelLive', width: 390, height: 620, min_width: 350, min_height: 600, style: UI::HtmlDialog::STYLE_DIALOG)
          @dialog.set_file(File.join(__dir__, 'html', 'live.html'))
          @dialog.add_action_callback('ready') { push }
          @dialog.add_action_callback('change') do |_, json|
            begin
              values = JSON.parse(json); values['size'] = Float(values['size']) / 25.4 / world_scale
              LiveBevel.update(@object, values); push
            rescue StandardError => e
              error(e.message); push
            end
          end
          @dialog.add_action_callback('step') do |_, direction|
            begin
              _, world = location
              size = Sketchup.active_model.active_view.pixels_to_model(1, @object.bounds.center).to_f / Geom::Vector3d.new(1, 0, 0).transform(world).length
              LiveBevel.update(@object, {'size' => [LiveBevel.data(@object)['size'] + direction.to_i * size, 0.001.mm].max}); push
            rescue StandardError => e; error(e.message); end
          end
          @dialog.add_action_callback('offset') { Sketchup.active_model.select_tool(InteractiveTool.new(@object)) }
          @dialog.add_action_callback('edit') do
            proxy, = LiveBevel.parts(@object)
            _, _, path = location
            Sketchup.active_model.active_path = path + [proxy]
          end
          @dialog.add_action_callback('commit') { finish(true) }
          @dialog.add_action_callback('remove') { finish(false) }
          current_dialog = @dialog
          @dialog.set_on_closed { @dialog = nil if @dialog == current_dialog }
        end
        @dialog.show; push
      end
      def location
        found = nil
        search = lambda do |mesh, world, path|
          mesh.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            t = world * e.transformation; p = path + [e]
            if e == @object then found = [e, t, p]; return end
            search.call(Modifier.entities(e), t, p) unless e.get_attribute(LiveBevel::KEY, 'role')
          end
        end
        search.call(Sketchup.active_model.entities, Geom::Transformation.new, [])
        found || [@object, @object.transformation, [@object]]
      end
      def push
        return unless @dialog && @object&.valid? && (values = LiveBevel.data(@object))
        payload = values.merge('size' => values['size'] * 25.4 * world_scale, 'language' => MeshTools.settings['language'])
        @dialog.execute_script("app.state(#{JSON.generate(payload)})")
      end
      def world_scale
        _, transform = location
        model = Sketchup.active_model
        transform = model.edit_transform if model.active_path&.include?(@object)
        axes = [Geom::Vector3d.new(1,0,0),Geom::Vector3d.new(0,1,0),Geom::Vector3d.new(0,0,1)].map { |a| a.transform(transform) }
        sizes = axes.map(&:length)
        raise Chamfer::Error, 'Live: сначала примените неравномерный масштаб объекта.' if sizes.min <= 1.0e-8 || sizes.max-sizes.min > sizes.max*1.0e-6 || axes.combination(2).any? { |a,b| a.dot(b).abs > a.length*b.length*1.0e-6 }
        sizes.first
      end
      def error(message)
        @dialog&.execute_script("app.error(#{JSON.generate(message)})")
      end
      def finish(commit)
        LiveBevel.finish(@object, commit)
      rescue StandardError => e; error(e.message)
      end
      def close
        dialog = @dialog; @dialog = nil; dialog&.close
      end
    end
    module PreferencesPanel
      module_function
      def show
        if @dialog then @dialog.bring_to_front; return end
        @dialog = UI::HtmlDialog.new(dialog_title: 'bevelchamfer — настройки', preferences_key: 'BACommunity_BevelPreferences', width: 390, height: 410, min_width: 350, min_height: 400, style: UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_file(File.join(__dir__, 'html', 'preferences.html'))
        @dialog.add_action_callback('ready') { @dialog.execute_script("app.state(#{JSON.generate(MeshTools.settings)})") }
        @dialog.add_action_callback('change') do |_, json|
          begin; MeshTools.save(JSON.parse(json))
          rescue StandardError => e; @dialog.execute_script("app.error(#{JSON.generate(e.message)})") end
        end
        @dialog.set_on_closed { @dialog = nil }; @dialog.show
      end
    end
  end
end
