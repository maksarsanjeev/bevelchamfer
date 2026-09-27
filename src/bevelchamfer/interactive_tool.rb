# Copyright 2026 B&A community. Licensed under Apache-2.0.
require 'sketchup.rb'
module BACommunity
  module BevelChamfer
    class InteractiveTool
      attr_reader :edges, :segments, :size, :phase
      def initialize(live_object = nil)
        @live_object = live_object; @edges = []; @hover = []; @phase = :selection
        @size = Sketchup.read_default('BACommunity_BevelTool', 'size', 20.mm).to_f
        @segments = Sketchup.read_default('BACommunity_BevelTool', 'segments', 8).to_i.clamp(1, 24)
        if live_object
          values = LiveBevel.data(live_object)
          @size = values['size'] * LivePanel.world_scale
          @segments = values['segments']
        end
        @input = Sketchup::InputPoint.new; @lines = []
      end
      def activate
        model = Sketchup.active_model
        unless @live_object
          items = model.selection.to_a
          objects = items.select { |o| o.is_a?(Sketchup::Group) || o.is_a?(Sketchup::ComponentInstance) }
          if objects.length == 1 && items.length == 1
            @object = objects.first
            @context = @object.definition; @transform = model.edit_transform * @object.transformation
            @edges = LiveBevel.eligible(Modifier.entities(@object))
          else
            @edges = items.flat_map { |e| e.is_a?(Sketchup::Edge) ? [e] : (e.is_a?(Sketchup::Face) ? e.edges : []) }.select { |e| eligible?(e) }.uniq
            @context = @edges.first&.parent; @transform = Geom::Transformation.new
          end
        end
        status
      rescue StandardError => e
        report(e); model.select_tool(nil)
      end
      def eligible?(e)
        e.is_a?(Sketchup::Edge) && e.valid? && !e.soft? && !e.hidden? && e.faces.length == 2 && e.faces[0].normal.angle_between(e.faces[1].normal) > 1.0e-6
      end
      def probe(x, y, view)
        @input.pick(view, x, y)
        if @live_object
          proxy, = LiveBevel.parts(@live_object)
          _, @transform = LivePanel.location
          @transform *= proxy.transformation
          return [] unless @input.valid?
          nearest = LiveBevel.eligible(proxy.entities).min_by { |e| @input.position.distance_to_line([e.start.position.transform(@transform), e.line[1].transform(@transform)]) }
          return nearest ? [nearest] : []
        end
        hit = @input.vertex || @input.edge || @input.face
        picked = case hit
                 when Sketchup::Vertex then hit.edges
                 when Sketchup::Face then hit.edges
                 when Sketchup::Edge then [hit]
                 else []
                 end
        picked = picked.select { |e| eligible?(e) }
        if @context && !@edges.empty?
          picked.select! { |e| e.parent == @context }
        elsif !picked.empty? && !@live_object
          helper = view.pick_helper; helper.do_pick(x, y)
          path = helper.count > 0 ? helper.path_at(0) : []
          objects = path.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          return [] if objects.any?(&:locked?)
          return [] if objects.any? { |e| LiveBevel.data(e) }
          return [] if objects[0...-1].any? { |e| e.definition.instances.length > 1 }
          @object = objects.last; @context = picked.first.parent
          @transform = Geom::Transformation.new
          objects.each { |o| @transform *= o.transformation }
        end
        picked
      end
      def onMouseMove(flags, x, y, view)
        @flags = flags; @hover = probe(x, y, view)
        if @phase == :offset && @input.valid?
          edge = @reference_edge
          point = @input.position
          line = [edge.start.position.transform(@transform), edge.end.position.transform(@transform) - edge.start.position.transform(@transform)]
          @size = point.distance(point.project_to_line(line)).to_f
          update_preview
        end
        status; view.invalidate
      end
      def choose(candidates, flags = 0)
        add = (flags & COPY_MODIFIER_MASK) != 0
        shift = (flags & CONSTRAIN_MODIFIER_MASK) != 0
        @edges = if add && shift then @edges - candidates
                 elsif add then (@edges + candidates).uniq
                 elsif shift then (@edges - candidates) + (candidates - @edges)
                 else candidates.dup
                 end
      end
      def onLButtonDown(flags, x, y, view)
        candidates = probe(x, y, view)
        if @live_object
          if @phase == :offset
            apply_current
          elsif !candidates.empty?
            @reference_edge = candidates.first
            @phase = :offset
          end
        elsif @phase == :offset
          apply_current
        elsif @edges.empty? || (flags & (COPY_MODIFIER_MASK | CONSTRAIN_MODIFIER_MASK)) != 0
          @last = nil; choose(candidates, flags)
        elsif @input.valid?
          @reference_edge = @edges.min_by { |e| @input.position.distance_to_line([e.start.position.transform(@transform), e.line[1].transform(@transform)]) }
          @phase = :offset; update_preview
        end
        status; view.invalidate
      rescue StandardError => e
        report(e)
      end
      def onLButtonDoubleClick(flags, x, y, view)
        @edges = probe(x, y, view) if @edges.empty? && !@live_object
        @size = Sketchup.read_default('BACommunity_BevelTool', 'size', 20.mm).to_f
        apply_current unless @edges.empty? && !@live_object
      rescue StandardError => e
        report(e)
      end
      def local_size
        axes = [Geom::Vector3d.new(1,0,0), Geom::Vector3d.new(0,1,0), Geom::Vector3d.new(0,0,1)].map { |a| a.transform(@transform || Geom::Transformation.new) }
        scales = axes.map(&:length)
        raise Chamfer::Error, 'Неравномерный масштаб: сначала примените масштаб объекта.' if scales.min <= 1.0e-8 || scales.max - scales.min > scales.max * 1.0e-6 || axes.combination(2).any? { |a,b| a.dot(b).abs > a.length*b.length*1.0e-6 }
        @size / scales.first
      end
      def update_preview
        return if @size <= 0
        targets = @live_object ? LiveBevel.eligible(LiveBevel.parts(@live_object).first.entities) : @edges
        return if targets.empty?
        mode = @live_object ? LiveBevel.data(@live_object)['mode'].to_sym : :offset
        @lines = Chamfer.preview_lines(Chamfer.plan(targets, local_size, @segments, mode))
        @error = nil
      rescue Chamfer::Error => e
        @lines = []; @error = e.message
      end
      def apply_current(repeat = false)
        if @live_object
          LiveBevel.update(@live_object, {'size' => @size / LivePanel.world_scale, 'segments' => @segments})
          LivePanel.push; @phase = :selection; return
        end
        raise Chamfer::Error, 'Выберите рёбра.' if @edges.empty? && !repeat
        model = Sketchup.active_model
        mesh = @context.entities
        # A session snapshot allows arrows/typed values to rebuild the last
        # operation without using Undo and without changing its source shape.
        if repeat
          current = @last && connected_geometry(@last[:entities].grep(Sketchup::Edge).select(&:valid?))
          raise Chamfer::Error, 'Модель изменилась после фаски. Выберите рёбра заново.' unless current && Modifier.signature(geometry_owner(current)) == @last[:signature]
          source = @last[:source]; keys = @last[:keys]
        else
          affected = connected_geometry(@edges)
          owner = geometry_owner(affected)
          source = Modifier.snapshot(owner); keys = @edges.map { |e| Modifier.edge_key(e) }
        end
        model.start_operation('bevelchamfer — интерактивная фаска', true)
        begin
          if !repeat && @object && @object.definition.instances.length > 1
            @object.make_unique
            @context = @object.definition; mesh = @context.entities
            @edges = Modifier.matching(mesh, keys)
          end
          if repeat
            old_entities = @last[:entities].select(&:valid?)
            mesh.erase_entities(old_entities)
            scratch = mesh.add_group
            Modifier.restore(scratch.entities, source)
            scratch.explode
          end
          targets = repeat ? Modifier.matching(mesh, keys) : @edges
          unrelated = mesh.to_a - connected_geometry(targets)
          Chamfer.apply(targets, local_size, @segments, mode: :offset, operation: false)
          affected = mesh.to_a - unrelated
          model.commit_operation
        rescue StandardError
          model.abort_operation; raise
        end
        owner = geometry_owner(affected)
        @last = {owner: owner, source: source, keys: keys, entities: affected, signature: Modifier.signature(owner)}
        Sketchup.write_default('BACommunity_BevelTool', 'size', @size)
        Sketchup.write_default('BACommunity_BevelTool', 'segments', @segments)
        @edges = []; @hover = []; @lines = []; @phase = :selection
        status
      end
      def geometry_owner(entities)
        Struct.new(:definition).new(Struct.new(:entities).new(entities))
      end
      def connected_geometry(edges)
        seen = {}; queue = edges.dup
        until queue.empty?
          e = queue.pop; next if seen[e]
          seen[e] = true
          neighbors = e.is_a?(Sketchup::Face) ? e.edges : (e.faces + e.vertices.flat_map(&:edges))
          neighbors.each { |item| queue << item unless seen[item] }
        end
        seen.keys
      end
      def onKeyDown(key, repeat, flags, view)
        return false unless [VK_UP, VK_DOWN].include?(key)
        @segments = (@segments + (key == VK_UP ? 1 : -1)).clamp(1, 24)
        if @last && @phase == :selection then apply_current(true) else update_preview end
        status; view.invalidate; true
      rescue StandardError => e
        report(e); true
      end
      def onUserText(text, view)
        parsed = Sketchup.parse_length(text)
        raise Chamfer::Error, 'Введите положительный размер, например 20mm.' unless parsed && parsed.to_f > 0
        @size = parsed.to_f
        apply_current(@last && @phase == :selection)
        view.invalidate
      rescue StandardError => e
        report(e)
      end
      def enableVCB?; true; end
      def onCancel(reason, view)
        if @phase == :offset
          @phase = :selection; @lines = []
        else
          @edges = []; @last = nil; @context = nil; @lines = []
        end
        status; view.invalidate
      end
      def status
        text = @phase == :offset ? 'Укажите размер мышью или введите число. Esc — вернуться к выбору.' : 'Выберите ребро, грань или вершину; Ctrl — добавить, Ctrl+Shift — исключить. Затем укажите опорную точку.'
        Sketchup.set_status_text(@error || "#{text} ↑/↓: #{@segments} сегм.")
        Sketchup.set_status_text('Размер', SB_VCB_LABEL); Sketchup.set_status_text(@size.to_l.to_s, SB_VCB_VALUE)
      end
      def draw(view)
        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(40, 120, 230)
        valid = @edges.select(&:valid?)
        points = valid.flat_map { |e| e.vertices.map { |v| v.position.transform(@transform) } }
        view.draw(GL_LINES, points) unless points.empty?
        removing = (@flags.to_i & (COPY_MODIFIER_MASK | CONSTRAIN_MODIFIER_MASK)) == (COPY_MODIFIER_MASK | CONSTRAIN_MODIFIER_MASK)
        view.drawing_color = removing ? Sketchup::Color.new(220, 55, 55) : Sketchup::Color.new(35, 185, 110)
        points = @hover.select(&:valid?).flat_map { |e| e.vertices.map { |v| v.position.transform(@transform || Geom::Transformation.new) } }
        view.draw(GL_LINES, points) unless points.empty?
        view.drawing_color = Sketchup::Color.new(40, 120, 230); view.line_width = 1
        @lines.each { |line| view.draw(GL_LINE_STRIP, line.map { |p| p.transform(@transform) }) }
        @input.draw(view) if @input.valid?
      end
      def getExtents
        box = Geom::BoundingBox.new
        @lines.each { |line| line.each { |p| box.add(p.transform(@transform)) } }
        box
      end
      def deactivate(view); view.invalidate; end
      def report(error); @error = error.message; Sketchup.set_status_text(@error); UI.beep; end
    end
  end
end
