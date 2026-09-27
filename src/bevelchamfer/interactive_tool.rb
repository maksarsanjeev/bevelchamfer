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
        @input = Sketchup::InputPoint.new; @lines = []; @reference_point = nil
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
        if (@flags.to_i & ALT_MODIFIER_MASK) != 0 && @input.edge && picked.include?(@input.edge)
          picked = connected_path(@input.edge)
        end
        picked
      end
      # Follow a unique edge, or an unmistakably tangent continuation at a
      # branch. A sharp or ambiguous junction ends the path.
      def connected_path(seed)
        path = [seed]
        seed.vertices.each do |start|
          vertex = start; previous = seed
          loop do
            choices = vertex.edges.select { |e| e != previous && eligible?(e) && e.parent == seed.parent }
            break if choices.empty?
            if choices.length == 1
              following = choices.first
            else
              direction = vertex.position - previous.other_vertex(vertex).position
              ranked = choices.map do |candidate|
                forward = candidate.other_vertex(vertex).position - vertex.position
                [candidate, direction.dot(forward) / (direction.length * forward.length)]
              end.sort_by { |_, score| -score }
              break if ranked[0][1] < Math.cos(45.degrees) || ranked[0][1] - ranked[1][1] < 0.15
              following = ranked[0][0]
            end
            break if path.include?(following)
            path << following
            vertex = following.other_vertex(vertex); previous = following
          end
        end
        path
      end
      def onMouseMove(flags, x, y, view)
        @flags = flags; @hover = probe(x, y, view)
        if @phase == :offset && @input.valid?
          point = @input.position
          @size = point.distance(point.project_to_line(reference_line)).to_f
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
        @flags = flags
        candidates = probe(x, y, view)
        if @live_object
          if @phase == :offset
            apply_current
          elsif !candidates.empty?
            @reference_edge = candidates.first
            @reference_point = @input.position.project_to_line(reference_line) if @input.valid?
            @phase = :offset
          end
        elsif @phase == :offset
          apply_current
        elsif @edges.empty? || (flags & (COPY_MODIFIER_MASK | CONSTRAIN_MODIFIER_MASK | ALT_MODIFIER_MASK)) != 0
          @last = nil; choose(candidates, flags); update_preview
        elsif @input.valid?
          @reference_edge = @edges.min_by { |e| @input.position.distance_to_line([e.start.position.transform(@transform), e.line[1].transform(@transform)]) }
          @reference_point = @input.position.project_to_line(reference_line)
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
        if @size <= 0
          @lines = []; @error = nil; return
        end
        targets = @live_object ? LiveBevel.eligible(LiveBevel.parts(@live_object).first.entities) : @edges
        if targets.empty?
          @lines = []; @error = nil; return
        end
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
        @edges = []; @hover = []; @lines = []; @reference_point = nil; @phase = :selection
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
        value = text.strip
        if @edges.empty? && @phase == :selection && value.match?(/\A\d+\z/)
          count = value.to_i
          raise Chamfer::Error, 'Сегментов должно быть от 1 до 24.' unless count.between?(1, 24)
          @segments = count
          @last ? apply_current(true) : update_preview
        else
          parts = value.split(/\s*;\s*|,\s+/)
          raise Chamfer::Error, 'Введите размер и, при необходимости, число сегментов.' unless parts.length.between?(1, 2)
          parsed = Sketchup.parse_length(parts.first)
          raise Chamfer::Error, 'Введите положительный размер, например 20mm.' unless parsed && parsed.to_f > 0
          if parts.length == 2
            count = Integer(parts.last, exception: false)
            raise Chamfer::Error, 'Сегментов должно быть от 1 до 24.' unless count && count.between?(1, 24)
            @segments = count
          end
          @size = parsed.to_f
          apply_current(@last && @phase == :selection)
        end
        status
        view.invalidate
      rescue StandardError => e
        report(e)
      end
      def enableVCB?; true; end
      def onCancel(reason, view)
        if @phase == :offset
          @phase = :selection; @reference_point = nil; update_preview
        else
          @edges = []; @last = nil; @context = nil; @reference_point = nil; @lines = []
        end
        @error = nil
        status; view.invalidate
      end
      def status
        text = @phase == :offset ? 'Укажите размер мышью или введите число. Esc — вернуться к выбору.' : 'Выберите ребро, грань или вершину; Alt — цепочка, Ctrl — добавить, Ctrl+Shift — исключить. Затем укажите опорную точку.'
        Sketchup.set_status_text(@error || "#{text} ↑/↓: #{@segments} сегм.")
        if @phase == :selection && @edges.empty?
          Sketchup.set_status_text('Сегменты', SB_VCB_LABEL)
          Sketchup.set_status_text(@segments.to_s, SB_VCB_VALUE)
        else
          Sketchup.set_status_text('Отступ, сегменты', SB_VCB_LABEL)
          Sketchup.set_status_text("#{@size.to_l}, #{@segments}", SB_VCB_VALUE)
        end
      end
      def reference_line
        start = @reference_edge.start.position.transform(@transform)
        [start, @reference_edge.end.position.transform(@transform) - start]
      end
      def onSetCursor
        cursor = self.class.cursor_id
        cursor ? UI.set_cursor(cursor) : false
      end
      def self.cursor_id
        return @cursor_id if defined?(@cursor_id)
        @cursor_id = UI.create_cursor(File.join(__dir__, 'icons', 'interactive.svg'), 2, 2)
      rescue StandardError
        @cursor_id = nil
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
        if @phase == :offset && @reference_point
          view.drawing_color = Sketchup::Color.new(220, 50, 50)
          if @input.valid?
            view.line_stipple = '.'; view.draw(GL_LINES, [@reference_point, @input.position]); view.line_stipple = ''
          end
          view.draw_points([@reference_point], 9, 3, Sketchup::Color.new(220, 50, 50))
        end
        @input.draw(view) if @input.valid?
      end
      def getExtents
        box = Geom::BoundingBox.new
        @lines.each { |line| line.each { |p| box.add(p.transform(@transform)) } }
        box.add(@reference_point) if @reference_point
        box
      end
      def deactivate(view); view.invalidate; end
      def report(error); @error = error.message; Sketchup.set_status_text(@error); UI.beep; end
    end
  end
end
