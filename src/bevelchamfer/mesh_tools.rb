# Copyright 2026 B&A community. Licensed under Apache-2.0.
require 'sketchup.rb'
module BACommunity
  module BevelChamfer
    module MeshTools
      module_function
      DEFAULTS = {'angle' => 30.0, 'smooth' => true, 'borders' => true, 'notifications' => true, 'language' => 'ru'}.freeze
      def settings
        DEFAULTS.to_h { |k, v| [k, Sketchup.read_default('BACommunity_BevelPreferences', k, v)] }
      end
      def save(values)
        angle = Float(values.fetch('angle'))
        raise Chamfer::Error, 'Угол должен быть от 0 до 180°.' unless angle.finite? && angle.between?(0, 180)
        raise Chamfer::Error, 'Неизвестный язык.' unless %w[ru en].include?(values.fetch('language', settings['language']))
        DEFAULTS.each_key do |k|
          value = case k
                  when 'angle' then angle
                  when 'language' then values.fetch(k, settings[k])
                  else !!values[k]
                  end
          Sketchup.write_default('BACommunity_BevelPreferences', k, value)
        end
      end
      def selected_edges
        model = Sketchup.active_model
        items = model.selection.empty? ? model.active_entities.to_a : model.selection.to_a
        items.flat_map { |e| e.is_a?(Sketchup::Edge) ? [e] : (e.is_a?(Sketchup::Face) ? e.edges : []) }.uniq
      end
      def border?(edge)
        return false unless edge.faces.length == 2
        marked = edge.faces.count { |f| f.get_attribute('BACommunity_BevelSurface', 'generated', false) }
        return marked == 1 if marked > 0
        # Imported bevels have no extension metadata. A border separates a
        # run of gradually changing facet normals from a locally flat face.
        a, b = edge.faces
        return true if curved_side?(a, edge) != curved_side?(b, edge)
        smaller, larger = [a, b].sort_by(&:area)
        larger.area >= smaller.area * 4 && curved_side?(smaller, edge)
      end
      def curved_side?(face, shared)
        face.edges.any? do |neighbor_edge|
          next false if neighbor_edge == shared || neighbor_edge.faces.length != 2
          other = neighbor_edge.faces.find { |f| f != face }
          angle = face.normal.angle_between(other.normal)
          angle > 1.0e-4 && angle < 45.degrees
        end
      end
      def soften(edges, values = settings)
        count = 0
        edges.each do |e|
          next unless e.valid?
          on = e.faces.length == 2 && values['angle'].to_f > 0 && e.faces[0].normal.angle_between(e.faces[1].normal) <= values['angle'].to_f.degrees + 1.0e-8
          e.soft = on
          e.smooth = on && values['smooth'] && (!border?(e) || values['borders'])
          count += 1 if on
        end
        count
      end
      def auto_soften
        operate('Сгладить рёбра') { |edges| soften(edges) }
      end
      def compatible?(a, b)
        a.material == b.material && a.back_material == b.back_material && a.layer == b.layer && a.hidden? == b.hidden? &&
          a.get_attribute('BACommunity_BevelSurface', 'generated') == b.get_attribute('BACommunity_BevelSurface', 'generated') &&
          !a.attribute_dictionaries&.any? { |d| d.name != 'BACommunity_BevelSurface' } &&
          !b.attribute_dictionaries&.any? { |d| d.name != 'BACommunity_BevelSurface' }
      end
      def clean(edges)
        count = 0
        edges.each do |e|
          next unless e.valid? && e.faces.length == 2 && !e.curve && !e.attribute_dictionaries
          a, b = e.faces
          next unless a.normal.samedirection?(b.normal) && compatible?(a, b)
          e.erase!; count += 1
        end
        # Native remove/restore of a straight edge merges redundant collinear
        # vertices while keeping adjacent faces; no crossing of context bounds.
        vertices = edges.select(&:valid?).flat_map(&:vertices).uniq
        vertices.each do |v|
          next unless v.valid? && v.edges.length == 2
          a, b = v.edges
          next if a.curve || b.curve || a.attribute_dictionaries || b.attribute_dictionaries
          next unless a.faces.sort_by(&:entityID) == b.faces.sort_by(&:entityID)
          next unless [:soft?, :smooth?, :hidden?, :layer, :material].all? { |p| a.send(p) == b.send(p) }
          va = a.other_vertex(v).position - v.position; vb = b.other_vertex(v).position - v.position
          next unless va.parallel?(vb) && va.dot(vb) < 0
          # SketchUp coalesces these via a temporary dividing edge.
          owner = a.parent.entities
          before = owner.grep(Sketchup::Edge).length
          temp = owner.add_line(v.position, v.position.offset(Geom::Vector3d.new(0.123, 0.456, 0.789), 0.1))
          temp.erase! if temp&.valid?
          count += [before - owner.grep(Sketchup::Edge).length, 0].max
        end
        count
      end
      def clean_edges
        operate('Очистить рёбра') { |edges| clean(edges) }
      end
      def operate(title)
        model = Sketchup.active_model; edges = selected_edges
        raise Chamfer::Error, 'Войдите внутрь группы или компонента, чтобы обработать его рёбра.' if edges.empty?
        model.start_operation("bevelchamfer — #{title}", true)
        begin
          count = yield(edges); model.commit_operation
        rescue StandardError
          model.abort_operation; raise
        end
        notify(title, edges.length, count) if settings['notifications']
        count
      end
      def notify(title, selected, count)
        english = settings['language'] == 'en'
        clean = title == 'Очистить рёбра'
        heading = english ? (clean ? 'Clean Edges' : 'Auto Soften Edges') : title
        selected_label = english ? 'Edges Selected' : 'Рёбер выбрано'
        result_label = english ? (clean ? 'Edges Cleaned' : 'Edges Softened') : (clean ? 'Рёбер удалено' : 'Рёбер смягчено')
        message = "#{heading}\n#{selected_label}: #{selected}\n#{result_label}: #{count}"
        Sketchup.set_status_text(message.tr("\n", ' '))
        extension = Sketchup.extensions['bevelchamfer']
        return unless extension
        icon = File.join(__dir__, 'icons', clean ? 'clean_24.png' : 'soften_24.png')
        @notification = UI::Notification.new(extension, message, icon)
        @notification.show
      end
    end
  end
end
