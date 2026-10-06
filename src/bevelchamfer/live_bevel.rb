# Copyright 2026 B&A community. Licensed under Apache-2.0.
require 'sketchup.rb'
require 'json'
module BACommunity
  module BevelChamfer
    module LiveBevel
      KEY = 'BACommunity_LiveBevel'.freeze
      module_function
      def data(object)
        raw = object.get_attribute(KEY, 'data'); raw && JSON.parse(raw)
      end
      def parts(object)
        children = Modifier.entities(object).grep(Sketchup::Group)
        [children.find { |g| g.get_attribute(KEY, 'role') == 'proxy' }, children.find { |g| g.get_attribute(KEY, 'role') == 'result' }]
      end
      def eligible(mesh)
        mesh.grep(Sketchup::Edge).select { |e| e.valid? && e.faces.length == 2 && !e.soft? && !e.hidden? && e.faces[0].normal.angle_between(e.faces[1].normal) > 1.0e-6 }
      end
      def create(object, size = 20.mm, segments = 8)
        raise Chamfer::Error, 'Live работает с одной группой или компонентом.' unless object.is_a?(Sketchup::Group) || object.is_a?(Sketchup::ComponentInstance)
        raise Chamfer::Error, 'Объект заблокирован.' if object.locked?
        return object if data(object)
        model = Sketchup.active_model
        transaction('Live') do
          saved = Modifier.data(object)
          Modifier.check(object, saved)
          source = saved ? saved['source'] : Modifier.snapshot(object)
          object.make_unique
          mesh = Modifier.entities(object); mesh.clear!
          proxy = mesh.add_group; proxy.name = 'bevelchamfer — исходник'
          proxy.set_attribute(KEY, 'role', 'proxy'); Modifier.restore(proxy.entities, source)
          result = mesh.add_group; result.name = 'bevelchamfer — результат'; result.set_attribute(KEY, 'role', 'result')
          payload = {'size' => size.to_f, 'segments' => segments, 'mode' => 'offset', 'display' => 'both', 'opacity' => 1.0, 'borders' => true}
          object.delete_attribute(Modifier::KEY)
          object.set_attribute(KEY, 'data', JSON.generate(payload))
          rebuild(object)
        end
        attach(model); object
      end
      def rebuild(object)
        proxy, result = parts(object); raise Chamfer::Error, 'Исходник или результат Live отсутствует.' unless proxy && result
        values = data(object)
        result.locked = false; result.entities.clear!
        copy = result.entities.add_instance(proxy.definition, Geom::Transformation.new); copy.explode
        edges = eligible(result.entities)
        raise Chamfer::Error, 'В исходнике нет подходящих рёбер.' if edges.empty?
        Chamfer.apply(edges, values['size'], values['segments'], mode: values['mode'].to_sym, operation: false)
        result.entities.grep(Sketchup::Edge).each { |e| e.smooth = !!values['borders'] if MeshTools.border?(e) }
        opacity(result, values['opacity'], object.material)
        values['source_signature'] = Modifier.signature(proxy)
        object.set_attribute(KEY, 'data', JSON.generate(values)); object.delete_attribute(KEY, 'error')
        result.locked = true
        display(object)
      end
      def opacity(result, alpha, inherited = nil)
        return if alpha >= 0.999
        cache = {}
        result.entities.grep(Sketchup::Face).each do |face|
          original = face.material || inherited
          key = original&.name || '__default'
          mat = cache[key] ||= begin
            name = "bevelchamfer прозрачность #{result.persistent_id} #{key}"
            made = Sketchup.active_model.materials[name] || Sketchup.active_model.materials.add(name)
            made.color = original ? original.color : Sketchup::Color.new(210, 215, 222)
            made.alpha = alpha
            made
          end
          face.set_attribute(KEY, 'original_material', face.material&.name || '')
          face.set_attribute(KEY, 'original_back_material', face.back_material&.name || '')
          face.material = mat; face.back_material = mat
        end
      end
      def display(object)
        proxy, result = parts(object); return unless proxy && result
        value = data(object)['display']
        editing = Sketchup.active_model.active_path&.include?(proxy)
        proxy.hidden = !editing && value != 'proxy'
        result.hidden = value == 'proxy'
        Sketchup.active_model.active_view.invalidate
      end
      def update(object, changes)
        raise Chamfer::Error, 'Объект заблокирован.' if object.locked?
        values = data(object).merge(changes)
        segment_value = values['segments']
        values['size'] = Float(values['size']); values['segments'] = Integer(segment_value); values['opacity'] = Float(values['opacity'])
        raise Chamfer::Error, 'Число сегментов должно быть целым.' unless Float(segment_value) == values['segments']
        raise Chamfer::Error, 'Размер должен быть больше нуля; сегменты — 1–24.' unless values['size'].finite? && values['size'] > 0 && values['segments'].between?(1, 24)
        raise Chamfer::Error, 'Неверный режим отображения.' unless %w[proxy bevel both].include?(values['display'])
        raise Chamfer::Error, 'Прозрачность должна быть от 0 до 100%.' unless values['opacity'].finite? && values['opacity'].between?(0, 1)
        raise Chamfer::Error, 'Неверный способ задания размера.' unless %w[offset radius].include?(values['mode'])
        transaction('параметры Live') do
          object.make_unique
          parts(object).each(&:make_unique)
          object.set_attribute(KEY, 'data', JSON.generate(values)); rebuild(object)
        end
      end
      def transaction(name, transparent = false)
        model = Sketchup.active_model; @busy = true
        path = model.active_path
        # SketchUp temporarily transforms the geometry of the open editing
        # path into model coordinates. Rebuild definitions in their local frame.
        model.active_path = nil if path
        model.start_operation("bevelchamfer — #{name}", true, false, transparent)
        begin
          yield; model.commit_operation
        rescue StandardError
          model.abort_operation; raise
        ensure
          if path
            parent = model.entities
            resolved = path.map do |old|
              role = old.valid? && old.get_attribute(KEY, 'role')
              entity = role ? parent.grep(Sketchup::Group).find { |e| e.get_attribute(KEY, 'role') == role } : old
              break unless entity&.valid? && parent.include?(entity)
              parent = Modifier.entities(entity)
              entity
            end
            model.active_path = resolved if resolved && !resolved.empty?
          end
          @busy = false
          walk(model.entities) { |o, _| display(o) }
        end
      end
      def finish(object, commit)
        proxy, result = parts(object)
        raise Chamfer::Error, 'Объект заблокирован.' if object.locked?
        transaction(commit ? 'запечь Live' : 'снять Live') do
          model = Sketchup.active_model
          path = model.active_path
          model.active_path = path.take_while { |e| e != object } if path&.include?(object)
          keep = commit ? result : proxy; discard = commit ? proxy : result
          discard.locked = false; discard.erase!
          keep.locked = false
          if commit
            keep.entities.grep(Sketchup::Face).each do |face|
              original = face.get_attribute(KEY, 'original_material')
              if original
                face.material = original.empty? ? nil : model.materials[original]
                back = face.get_attribute(KEY, 'original_back_material', '')
                face.back_material = back.empty? ? nil : model.materials[back]
                face.delete_attribute(KEY)
              end
            end
          end
          keep.explode
          object.delete_attribute(KEY)
        end
        LivePanel.close if defined?(LivePanel)
      end
      def walk(mesh, transform = Geom::Transformation.new, &block)
        mesh.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          next if e.get_attribute(KEY, 'role')
          world = transform * e.transformation
          data(e) ? block.call(e, world) : walk(Modifier.entities(e), world, &block)
        end
      end
      def live_present?(model)
        walk(model.entities) { |_object, _world| return true }
        false
      end
      def changed_live_objects(model)
        changed = []
        walk(model.entities) do |object, _world|
          proxy, result = parts(object)
          next unless proxy && result
          changed << object if Modifier.signature(proxy) != data(object)['source_signature']
        end
        changed
      end
      def sync(model = Sketchup.active_model)
        return if @busy || model != Sketchup.active_model || !live_present?(model)
        # Merely opening/undoing an ordinary group must not switch edit context:
        # active_path= creates transparent transactions and can eat Undo steps.
        return if changed_live_objects(model).empty?
        path = model.active_path
        @busy = true; model.active_path = nil if path
        @busy = false
        walk(model.entities) do |object, _|
          proxy, result = parts(object); next unless proxy && result
          if Modifier.signature(proxy) != data(object)['source_signature']
            begin
              # Validate the full build in a separate reversible operation.
              # Aborting a transparent operation would undo the user's edit.
              model.start_operation('bevelchamfer — проверка Live', true)
              @busy = true
              begin
                scratch = model.entities.add_group
                scratch.entities.add_instance(proxy.definition, Geom::Transformation.new).explode
                Chamfer.apply(eligible(scratch.entities), data(object)['size'], data(object)['segments'], mode: data(object)['mode'].to_sym, operation: false)
              ensure
                model.abort_operation
                @busy = false
              end
              transaction('пересчёт Live', true) { rebuild(object) }
            rescue StandardError => e
              object.set_attribute(KEY, 'error', e.message)
              Sketchup.set_status_text("Live: #{e.message}")
              LivePanel.error(e.message) if defined?(LivePanel)
            end
          end
        end
      ensure
        if path && path.all?(&:valid?)
          @busy = true; model.active_path = path; @busy = false
          walk(model.entities) { |o, _| display(o) }
        end
      end
      def schedule(model)
        return if @busy || @pending || model != Sketchup.active_model || !live_present?(model)
        @pending = true
        UI.start_timer(0.05, false) do
          @pending = false; sync(model)
        end
      end
      class Observer < Sketchup::ModelObserver
        def onTransactionCommit(model); LiveBevel.schedule(model); end
        def onTransactionUndo(model); LiveBevel.schedule(model); end
        def onTransactionRedo(model); LiveBevel.schedule(model); end
        def onActivePathChanged(model)
          return if LiveBevel.instance_variable_get(:@busy)
          owner = model.active_path&.find { |o| LiveBevel.data(o) }
          if owner
            LivePanel.show(owner)
            proxy, = LiveBevel.parts(owner)
            if model.active_path.last == owner
              UI.start_timer(0, false) { model.active_path = model.active_path + [proxy] if owner.valid? && model.active_path&.last == owner }
            end
          else
            LivePanel.close
          end
          LiveBevel.walk(model.entities) { |o, _| LiveBevel.display(o) }
        end
      end
      class AppObserver < Sketchup::AppObserver
        def expectsStartupModelNotifications; true; end
        def onNewModel(model); LiveBevel.attach(model) if LiveBevel.live_present?(model); end
        def onOpenModel(model); LiveBevel.attach(model) if LiveBevel.live_present?(model); end
      end
      class WireOverlay < Sketchup::Overlay
        def initialize; super('BACommunity.BevelChamfer.LiveWire', 'bevelchamfer — исходник'); end
        def draw(context)
          LiveBevel.walk(Sketchup.active_model.entities) do |o, world|
            next unless LiveBevel.data(o)['display'] == 'both'
            proxy, = LiveBevel.parts(o); next unless proxy
            points = proxy.entities.grep(Sketchup::Edge).flat_map { |e| e.vertices.map { |v| v.position.transform(world * proxy.transformation) } }
            context.drawing_color = Sketchup::Color.new(65, 115, 178); context.line_width = 1
            context.draw(GL_LINES, points) unless points.empty?
          end
        end
        def getExtents; Sketchup.active_model.bounds; end
      end
      def attach(model)
        @observers ||= {}; return if @observers[model]
        observer = Observer.new; model.add_observer(observer); @observers[model] = observer
        overlay = WireOverlay.new; model.overlays.add(overlay); overlay.enabled = true
      end
      def start
        model = Sketchup.active_model
        attach(model) if live_present?(model)
        @app_observer ||= AppObserver.new
        Sketchup.add_observer(@app_observer) unless @app_attached
        @app_attached = true
      end
    end
  end
end
