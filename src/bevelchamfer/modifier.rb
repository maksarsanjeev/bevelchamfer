# Copyright 2026 B&A community
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'sketchup.rb'
require 'json'
require 'digest'

module BACommunity
  module BevelChamfer
    # Исходная сетка хранится в атрибуте объекта, переживает сохранение SKP и purge.
    # Для вложенной геометрии, текстур и пользовательских атрибутов используйте
    # обычную фаску: пересборка такого объекта потеряла бы дополнительные данные.
    module Modifier
      KEY = 'BACommunity_BevelChamfer'.freeze
      module_function

      def entities(object)
        object.is_a?(Sketchup::Group) ? object.entities : object.definition.entities
      end

      def data(object)
        raw = object.get_attribute(KEY, 'data')
        raw && JSON.parse(raw)
      end

      def point_key(point)
        point.to_a.map { |v| n = v.round(8); n.zero? ? 0.0 : n }
      end

      def edge_key(edge)
        [point_key(edge.start.position), point_key(edge.end.position)].sort
      end

      def snapshot(object)
        mesh = entities(object)
        raise Chamfer::Error, 'Параметрический режим поддерживает только рёбра и грани без вложенных объектов.' unless mesh.all? { |e| e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge) }
        raise Chamfer::Error, 'Для геометрии с атрибутами используйте обычную фаску.' if mesh.any? { |e| e.attribute_dictionaries && e.attribute_dictionaries.length > 0 }
        raise Chamfer::Error, 'Для дуг и кривых используйте обычную фаску: параметрический режим хранит полигональную сетку.' if mesh.grep(Sketchup::Edge).any?(&:curve)
        faces = mesh.grep(Sketchup::Face).map do |f|
          raise Chamfer::Error, 'Для текстур используйте обычную фаску: параметрический режим не сохраняет UV-развёртку.' if [f.material, f.back_material].compact.any?(&:texture)
          loops = [f.outer_loop] + f.loops.reject(&:outer?)
          {'loops' => loops.map { |l| l.vertices.map { |v| v.position.to_a } },
           'normal' => f.normal.to_a, 'front' => f.material&.name,
           'back' => f.back_material&.name, 'tag' => f.layer.name,
           'hidden' => f.hidden?}
        end
        edges = mesh.grep(Sketchup::Edge).map do |e|
          {'points' => [e.start.position.to_a, e.end.position.to_a],
           'soft' => e.soft?, 'smooth' => e.smooth?, 'hidden' => e.hidden?,
           'tag' => e.layer.name, 'material' => e.material&.name}
        end
        {'faces' => faces, 'edges' => edges}
      end

      def signature(object)
        mesh = entities(object)
        rows = mesh.map do |e|
          common = [e.layer.name, e.hidden?, e.material&.name,
                    e.attribute_dictionaries&.map { |a| [a.name, a.to_a] }]
          case e
          when Sketchup::Edge
            ['e', edge_key(e), e.soft?, e.smooth?, common]
          when Sketchup::Face
            ['f', e.loops.map { |l| [l.outer?, l.vertices.map { |v| point_key(v.position) }.sort] }.sort_by(&:to_s),
             point_key(e.normal), e.back_material&.name, common]
          else
            [e.typename, e.persistent_id, common]
          end
        end
        Digest::SHA256.hexdigest(JSON.generate(rows.sort_by(&:to_s)))
      end

      def check(object, saved)
        raise Chamfer::Error, 'Объект заблокирован.' if object.locked?
        if saved && signature(object) != saved['result']
          raise Chamfer::Error, 'Геометрия изменена вручную. Нажмите «Запечь», чтобы сохранить правки и снять модификатор.'
        end
      end

      def restore(mesh, source)
        model = Sketchup.active_model
        mesh.clear!
        source['faces'].each do |s|
          made = Chamfer.rebuild_face(mesh, loops: s['loops'].map { |l| l.map { |p| Geom::Point3d.new(p) } },
            normal: Geom::Vector3d.new(s['normal']), layer: model.layers[s['tag']] || model.layers[0],
            front: (s['front'] && model.materials[s['front']]), back: (s['back'] && model.materials[s['back']]))
          made.each { |f| f.hidden = s['hidden'] }
        end
        existing = mesh.grep(Sketchup::Edge).to_h { |e| [edge_key(e), e] }
        source['edges'].each do |s|
          key = s['points'].map { |p| point_key(Geom::Point3d.new(p)) }.sort
          edge = existing[key] || mesh.add_line(*s['points'])
          raise Chamfer::Error, 'Не удалось восстановить исходное ребро.' unless edge
          edge.soft = s['soft']; edge.smooth = s['smooth']; edge.hidden = s['hidden']
          edge.layer = model.layers[s['tag']] || model.layers[0]
          edge.material = (s['material'] && model.materials[s['material']])
        end
      end

      def matching(mesh, keys)
        found = mesh.grep(Sketchup::Edge).select { |e| keys.include?(edge_key(e)) }
        raise Chamfer::Error, 'Не удалось восстановить выбранные рёбра.' unless found.length == keys.length
        found
      end

      def apply(object, edges, size, segments, mode)
        saved = data(object)
        check(object, saved)
        source = saved ? saved['source'] : snapshot(object)
        keys = saved ? saved['edges'] : edges.map { |e| edge_key(e) }
        model = Sketchup.active_model
        model.start_operation('bevelchamfer — параметры фаски', true)
        begin
          object.make_unique
          mesh = entities(object)
          restore(mesh, source)
          result = Chamfer.apply(matching(mesh, keys), size, segments, mode: mode, operation: false)
          payload = {'schema' => 1, 'source' => source, 'edges' => keys,
                     'size' => size.to_f, 'segments' => segments, 'mode' => mode.to_s,
                     'result' => signature(object)}
          object.set_attribute(KEY, 'data', JSON.generate(payload))
          model.commit_operation
          result
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      # План модификатора считаем на временной копии исходника. Операция всегда
      # отменяется; результат и история Undo не меняются, в инструмент идут точки.
      def preview(object, size, segments, mode)
        saved = data(object)
        check(object, saved)
        return Chamfer.preview_lines(Chamfer.plan(entities(object).grep(Sketchup::Edge), size, segments, mode)) unless saved
        model = Sketchup.active_model
        model.start_operation('bevelchamfer — расчёт', true)
        begin
          scratch = model.entities.add_group
          restore(scratch.entities, saved['source'])
          plan = Chamfer.plan(matching(scratch.entities, saved['edges']), size, segments, mode)
          Chamfer.preview_lines(plan)
        ensure
          model.abort_operation
        end
      end

      def bake(object)
        raise Chamfer::Error, 'Объект заблокирован.' if object.locked?
        return unless data(object)
        model = Sketchup.active_model
        model.start_operation('bevelchamfer — запечь', true)
        begin
          object.delete_attribute(KEY)
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
      end
    end
  end
end
