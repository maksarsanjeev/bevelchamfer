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

module BACommunity
  module BevelChamfer

    # Движок фаски и скругления.
    #
    # Работаем не булевой операцией, а топологией: смежные грани подрезаются
    # на величину отступа, вдоль ребра встаёт полоса из segments сегментов,
    # в вершинах полосы сшиваются между собой. Отсюда три плюса против
    # «вырезать цилиндром»: не нужен ни Pro, ни солид; сохраняются материалы;
    # на стыке трёх рёбер получается настоящий сферический патч, а не клюв.
    #
    # Порядок работы:
    #   1. plan  — чистый расчёт, модель не трогается вообще;
    #   2. build — одна операция отмены: снести затронутое, поставить новое.
    module Chamfer

      Error = ChamferMath::Error

      # Точки ближе этого считаем одной и той же: SketchUp всё равно склеит.
      WELD = 0.001

      # infos   — EdgeInfo по каждому выбранному ребру
      # cuts    — [ребро, вершина] => ломаная, которой полоса кончается
      # patches — сферические патчи в вершинах, где сошлись три ребра
      # loops   — грань => массив петель, петля — массив точек
      Plan = Struct.new(:infos, :cuts, :patches, :loops, :faces, :edges, :notes)

      # --- 1. План -----------------------------------------------------------

      def self.plan(edges, size, segments, mode)
        raise Error, 'Размер должен быть конечным положительным числом.' unless size.to_f.finite? && size.to_f > 0
        raise Error, 'Сегментов: от 1 до 200.' unless segments.is_a?(Integer) && (1..200).cover?(segments)
        raise Error, 'Неизвестный режим размера.' unless [:radius, :offset].include?(mode)
        raise Error, 'Выделите рёбра одного объекта.' if edges.empty? || edges.any? { |e| !e.valid? } || edges.map(&:parent).uniq.length != 1
        infos = {}
        notes = Hash.new(0)
        edges.each do |edge|
          begin
            infos[edge] = ChamferMath::EdgeInfo.new(edge, size, segments, mode)
          rescue Error => e
            # Негодные рёбра не валят всю операцию: выделив коробку целиком,
            # пользователь заведомо захватит и рёбра сглаживания, и висячие.
            notes[e.message] += 1
          end
        end
        raise Error, 'среди выбранного нет рёбер, которые можно скруглить' if infos.empty?

        by_vertex = Hash.new { |h, k| h[k] = [] }
        infos.each_value do |info|
          by_vertex[info.edge.start] << info
          by_vertex[info.edge.end]   << info
        end

        cuts    = {}
        patches = []
        by_vertex.each { |vertex, incident| plan_vertex(vertex, incident, cuts, patches) }

        check_strips(infos, cuts)

        faces = by_vertex.keys.flat_map(&:faces).uniq
        loops = {}
        faces.each { |face| loops[face] = plan_face(face, infos, by_vertex, cuts) }

        Plan.new(infos, cuts, patches, loops, faces,
                 by_vertex.keys.flat_map(&:edges).uniq, notes)
      end

      # Слишком большой размер сначала выворачивает полосу: торцы в вершинах
      # заходят друг за друга, и рельсы идут против ребра. Ловим это здесь,
      # пока модель не тронута, — иначе превью нарисует кашу, а «Применить»
      # её ещё и построит.
      def self.check_strips(infos, cuts)
        infos.each_value do |info|
          head = cuts[[info.edge, info.edge.start]]
          tail = cuts[[info.edge, info.edge.end]]
          next if head.nil? || tail.nil?
          head.each_index do |i|
            next if (tail[i] - head[i]).dot(info.dir) > GeomUtils::TOL
            raise Error, 'размер больше длины ребра — уменьшите размер'
          end
        end
      end

      # Ломаные для превью во вьюпорте: торцы полос, рёбра сегментов и дуги
      # угловых патчей. Считается по плану, модель при этом не трогается.
      def self.preview_lines(plan)
        lines = []
        plan.infos.each_value do |info|
          head = plan.cuts[[info.edge, info.edge.start]]
          tail = plan.cuts[[info.edge, info.edge.end]]
          next if head.nil? || tail.nil?
          lines << head << tail
          head.each_index { |i| lines << [head[i], tail[i]] }
        end
        plan.patches.each { |patch| patch[:arcs].each { |arc| lines << arc } }
        lines
      end

      # --- 1a. Вершины -------------------------------------------------------

      # Полосу в вершине надо чем-то обрезать. Чем именно — зависит от того,
      # сколько скругляемых рёбер в этой вершине сошлось.
      def self.plan_vertex(vertex, incident, cuts, patches)
        case incident.length
        when 1 then plan_vertex_single(vertex, incident.first, cuts)
        when 2 then plan_vertex_pair(vertex, incident, cuts)
        when 3 then plan_vertex_triple(vertex, incident, cuts, patches)
        else
          raise Error, "в одной вершине сошлось #{incident.length} скругляемых рёбер — " \
                       'такой узел пока не поддержан'
        end
      end

      # Одно ребро. Режем плоскостью грани, в которую ребро упирается: тогда
      # торец полосы ложится ровно в эту грань и дырки не остаётся.
      def self.plan_vertex_single(vertex, info, cuts)
        rest = vertex.faces - [info.f1, info.f2]
        plane =
          case rest.length
          when 0 then [vertex.position, info.direction_from(vertex)] # открытый торец
          when 1 then GeomUtils.face_plane(rest.first)
          else
            raise Error, 'ребро упирается сразу в несколько граней — узел пока не поддержан'
          end
        cuts[[info.edge, vertex]] = rails_on_plane(info, info.f1, plane)
      end

      # Два ребра — ус. Обе полосы обязаны кончиться ОДНОЙ ломаной, иначе на
      # стыке будет щель. Берём пересечение одноимённых рельсов, развернув
      # профили от общей грани, — тогда индексы у обоих рёбер про одно и то же.
      def self.plan_vertex_pair(vertex, incident, cuts)
        a, b = incident
        shared = [a.f1, a.f2] & [b.f1, b.f2]
        raise Error, 'у двух рёбер в вершине нет общей грани — узел пока не поддержан' if shared.empty?

        pa = a.profile_from(shared.first)
        pb = b.profile_from(shared.first)
        raise Error, 'у соседних рёбер разное число сегментов' if pa.length != pb.length

        line = (0...pa.length).map do |i|
          GeomUtils.line_line(pa[i], a.dir, pb[i], b.dir) || miter_point(vertex, a, b, pa[i], pb[i])
        end

        cuts[[a.edge, vertex]] = orient_to(line, a)
        cuts[[b.edge, vertex]] = orient_to(line, b)
      end

      # Рельсы скрестились, а не пересеклись (несимметричный узел): режем оба
      # плоскостью уса и берём середину — шов всё равно остаётся общим.
      def self.miter_point(vertex, a, b, point_a, point_b)
        da = a.direction_from(vertex)
        db = b.direction_from(vertex)
        normal = GeomUtils.unit(Geom::Vector3d.new(da.x - db.x, da.y - db.y, da.z - db.z)) || da
        plane = [vertex.position, normal]
        qa = GeomUtils.line_plane([point_a, a.dir], plane) || point_a
        qb = GeomUtils.line_plane([point_b, b.dir], plane) || point_b
        Geom::Point3d.new((qa.x + qb.x) / 2.0, (qa.y + qb.y) / 2.0, (qa.z + qb.z) / 2.0)
      end

      # Три ребра — угол коробки. Осевые линии дуг всех трёх рёбер сходятся в
      # одной точке: это центр вписанной в угол сферы. Режем каждую полосу
      # поперёк через этот центр — торцы лягут ровно на сферу, а дырку между
      # ними закроет сферический треугольник.
      def self.plan_vertex_triple(vertex, incident, cuts, patches)
        a, b, c = incident
        center = axis_meet(vertex, a, b) || axis_meet(vertex, b, c) || axis_meet(vertex, a, c)
        raise Error, 'оси дуг в вершине не сошлись — узел пока не поддержан' if center.nil?

        arcs = incident.map do |info|
          pts = rails_on_plane(info, info.f1, [center, info.direction_from(vertex)])
          cuts[[info.edge, vertex]] = pts
          pts
        end
        generalized = incident.map(&:convex?).uniq.length > 1
        if generalized
          arcs = incident.map do |info|
            others = incident - [info]
            corners = [info.f1, info.f2].map do |face|
              neighbor = others.find { |other| [other.f1, other.f2].include?(face) }
              raise Error, 'не удалось соединить грани угла' unless neighbor
              offset_meet(face, info, neighbor, vertex)
            end
            profile = info.profile_at(vertex.position)
            shifts = [corners[0] - profile.first, corners[1] - profile.last].map { |v| v.dot(info.dir) }
            points = profile.each_with_index.map { |p, i| p.offset(info.dir, shifts[0] + (shifts[1]-shifts[0])*i.to_f/info.segments) }
            cuts[[info.edge, vertex]] = points
            points
          end
        end
        patches << { center: center, arcs: arcs, generalized: generalized, convex: a.convex?, front: a.f1_material, back: a.f1_back_material, layer: a.f1_layer }
      end

      def self.axis_meet(vertex, a, b)
        GeomUtils.line_line(a.center_at(vertex.position), a.dir,
                            b.center_at(vertex.position), b.dir)
      end

      # Пересечение всех рельсов ребра с плоскостью. from — грань, от которой
      # считается порядок точек: индекс 0 лежит на ней.
      def self.rails_on_plane(info, from, plane)
        info.profile_from(from).map do |point|
          GeomUtils.line_plane([point, info.dir], plane) ||
            raise(Error, 'ребро параллельно грани, в которую упирается')
        end
      end

      # Разворачивает общую ломаную так, чтобы её индекс 0 лежал на f1 ребра.
      def self.orient_to(line, info)
        section = nearest_on_edge(info, line.first)
        d1 = line.first.distance(info.tangent_on(info.f1, section)).to_f
        d2 = line.first.distance(info.tangent_on(info.f2, section)).to_f
        d1 <= d2 ? line.dup : line.reverse
      end

      # Проекция точки на прямую ребра: сравнивать с касательными надо в том же
      # сечении, а не в начале ребра.
      def self.nearest_on_edge(info, point)
        GeomUtils.along(info.a, info.dir, (point - info.a).dot(info.dir))
      end

      # --- 1b. Грани ---------------------------------------------------------

      def self.plan_face(face, infos, by_vertex, cuts)
        face.loops.map { |loop| plan_loop(face, loop, infos, by_vertex, cuts) }
      end

      def self.plan_loop(face, loop, infos, by_vertex, cuts)
        edges = loop.edges
        vertices = []
        corners = edges.each_index.map do |i|
          prev_edge = edges[i]
          next_edge = edges[(i + 1) % edges.length]
          vertex = (prev_edge.vertices & next_edge.vertices).first
          raise Error, 'петля грани разорвана' if vertex.nil?
          vertices << vertex
          corner(face, vertex, prev_edge, next_edge, infos, by_vertex, cuts)
        end
        check_loop(vertices, corners)
        corners.flatten(1)
      end

      # Слишком большой отступ съедает грань: новая кромка идёт против
      # прежней, и петля выворачивается наизнанку. Сравниваем направление
      # каждого нового отрезка с исходным ребром между теми же вершинами.
      def self.check_loop(vertices, corners)
        n = vertices.length
        n.times do |i|
          from = vertices[i].position
          to   = vertices[(i + 1) % n].position
          orig = to - from
          fresh = corners[(i + 1) % n].first - corners[i].last
          next if orig.length.to_f < GeomUtils::TOL
          next if fresh.dot(orig) > GeomUtils::TOL * orig.length.to_f
          raise Error, 'размер слишком велик для грани — уменьшите размер'
        end
      end

      # Во что превращается один угол петли. Правило простое: если хоть одно
      # из двух рёбер петли режется — угол задают линии отступа, а рёбра,
      # уходящие из грани, на него не влияют (их полосы обрезаны усом или
      # сферой и до этой грани не достают). Если не режется ни одно, но ребро
      # упирается в грань снаружи — угол заменяется торцом его полосы.
      def self.corner(face, vertex, prev_edge, next_edge, infos, by_vertex, cuts)
        prev_info = infos[prev_edge]
        next_info = infos[next_edge]
        return [offset_meet(face, prev_info, next_info, vertex)] if prev_info && next_info
        return [offset_edge_meet(face, prev_info, next_edge, vertex)] if prev_info
        return [offset_edge_meet(face, next_info, prev_edge, vertex)] if next_info

        incident = by_vertex.key?(vertex) ? by_vertex[vertex] : []
        return [vertex.position] if incident.empty?
        if incident.length > 1
          raise Error, 'в грань упирается несколько скругляемых рёбер сразу — узел пока не поддержан'
        end

        info = incident.first
        line = cuts[[info.edge, vertex]]
        across = (prev_edge.faces - [face]).first
        info.f1 == across ? line.dup : line.reverse
      end

      # Оба ребра петли режутся: угол — пересечение двух линий отступа.
      def self.offset_meet(face, a, b, vertex)
        la = a.offset_line(face)
        lb = b.offset_line(face)
        GeomUtils.line_line(la[0], la[1], lb[0], lb[1]) ||
          a.tangent_on(face, nearest_on_edge(a, vertex.position))
      end

      # Режется одно: угол — пересечение линии отступа с прямой соседнего ребра.
      def self.offset_edge_meet(face, info, other, vertex)
        line = info.offset_line(face)
        dir = GeomUtils.unit(other.end.position - other.start.position)
        meet = dir && GeomUtils.line_line(line[0], line[1], other.start.position, dir)
        meet || info.tangent_on(face, nearest_on_edge(info, vertex.position))
      end

      # --- 2. Сборка ---------------------------------------------------------

      Result = Struct.new(:edges, :faces, :notes)

      def self.apply(edges, size, segments, mode: :radius, smooth: true, operation: true)
        model = Sketchup.active_model
        plan = plan(edges, size, segments, mode)
        owner = edges.first.parent
        entities = owner.entities
        solid_instance = owner.is_a?(Sketchup::ComponentDefinition) && owner.instances.find(&:valid?)
        was_solid = solid_instance && solid_instance.manifold?

        # Всё, что читается из модели, снимаем ДО сноса: после erase объекты
        # мертвы, а материал, сторона и торцы полос нам ещё понадобятся.
        rebuild = plan.loops.map do |face, loops|
          { loops: loops, normal: face.normal, layer: face.layer,
            front: face.material, back: face.back_material }
        end
        strips = plan.infos.each_value.map do |info|
          { info: info,
            head: plan.cuts[[info.edge, info.edge.start]],
            tail: plan.cuts[[info.edge, info.edge.end]] }
        end

        model.start_operation('Фаска', true) if operation
        begin
          entities.erase_entities(plan.edges.select(&:valid?))

          made = []
          rebuild.each { |spec| made.concat(rebuild_face(entities, spec)) }
          strips.each { |strip| made.concat(build_strip(entities, strip, smooth)) }
          plan.patches.each { |patch| made.concat(build_patch(entities, patch, smooth)) }

          raise Error, 'После построения нарушилась замкнутость объекта; операция отменена.' if was_solid && !solid_instance.manifold?
          model.commit_operation if operation
          Result.new(plan.infos.length, made.length, plan.notes)
        rescue StandardError
          model.abort_operation if operation
          raise
        end
      end

      # Подрезанная грань встаёт на место прежней с тем же материалом.
      def self.rebuild_face(entities, spec)
        outer = weld(spec[:loops].first)
        return [] if outer.length < 3

        face = entities.add_face(outer)
        raise Error, 'Не удалось построить грань; операция отменена.' if face.nil?
        face.reverse! if face.normal.dot(spec[:normal]) < 0
        face.material      = spec[:front]
        face.back_material = spec[:back]
        face.layer         = spec[:layer]

        # Внутренние петли — дырки: обводим их рёбрами и убираем накрывшую грань.
        spec[:loops].drop(1).each do |hole|
          points = weld(hole)
          next if points.length < 3
          entities.add_face(points)
          patch = entities.grep(Sketchup::Face).find { |f| f.loops.length == 1 && hole_face?(f, points) }
          patch.erase! if patch
        end
        # После разбиения SketchUp может оставить исходный объект Face на
        # внутреннем участке. Ищем внешнюю грань заново по её внешней петле.
        face = entities.grep(Sketchup::Face).find { |f| hole_face?(f, outer) }
        raise Error, 'Не удалось восстановить внешнюю грань с отверстиями.' unless face
        face.reverse! if face.normal.dot(spec[:normal]) < 0
        face.material = spec[:front]
        face.back_material = spec[:back]
        face.layer = spec[:layer]
        [face]
      end

      def self.hole_face?(face, points)
        positions = face.outer_loop.vertices.map(&:position)
        positions.length == points.length &&
          points.all? { |p| positions.any? { |q| p.distance(q).to_f < WELD } }
      end

      # Полоса вдоль ребра: N четырёхугольников между торцами.
      def self.build_strip(entities, strip, smooth)
        info = strip[:info]
        head = strip[:head]
        tail = strip[:tail]
        return [] if head.nil? || tail.nil?

        quads = []
        (0...info.segments).each do |i|
          made = add_faces(entities, [head[i], head[i + 1], tail[i + 1], tail[i]])
          made.each do |face|
            orient(face, info)
            face.material      = info.f1_material
            face.back_material = info.f1_back_material
            face.layer = info.f1_layer
          end
          quads.concat(made)
        end

        quads.select!(&:valid?)
        quads.each { |face| face.set_attribute('BACommunity_BevelSurface', 'generated', true) }
        soften(quads, smooth && info.segments > 1)
        quads
      end

      # Сферический треугольник в углу: строки идут от дуги PQ к вершине R,
      # обе боковые стороны — те же дуги, что и торцы полос, поэтому шва нет.
      def self.build_patch(entities, patch, smooth)
        return build_transition_patch(entities, patch, smooth) if patch[:generalized]
        center = patch[:center]
        corners = triangle_corners(patch[:arcs])
        p, q, r = corners
        n = patch[:arcs].first.length - 1

        rows = (0..n).map do |i|
          t = i.to_f / n
          pa = center + GeomUtils.slerp(p - center, r - center, t)
          pb = center + GeomUtils.slerp(q - center, r - center, t)
          steps = n - i
          steps.zero? ? [pa] : (0..steps).map { |j| center + GeomUtils.slerp(pa - center, pb - center, j.to_f / steps) }
        end

        made = []
        (0...n).each do |i|
          top = rows[i]
          bottom = rows[i + 1]
          (0...(top.length - 1)).each do |j|
            points = j < bottom.length - 1 ? [top[j], top[j + 1], bottom[j + 1], bottom[j]] : [top[j], top[j + 1], bottom[j]]
            add_faces(entities, points).each do |face|
              out = GeomUtils.unit(face.bounds.center - center)
              out = out.reverse unless patch[:convex]
              face.reverse! if out && face.normal.dot(out) < 0
              face.material = patch[:front]
              face.back_material = patch[:back]
              face.layer = patch[:layer]
              made << face
            end
          end
        end
        made.select!(&:valid?)
        made.each { |face| face.set_attribute('BACommunity_BevelSurface', 'generated', true) }
        soften_all(made, smooth && n > 1)
        made
      end

      # A triangular transfinite patch has exactly the three rail-cut curves
      # as its boundary. Mixed convex/concave junctions have no common sphere.
      def self.build_transition_patch(entities, patch, smooth)
        a, b, c = triangle_corners(patch[:arcs])
        n = patch[:arcs].first.length - 1
        curve = lambda do |from, to|
          arc = patch[:arcs].find { |x| [x.first, x.last].all? { |p| p.distance(from).to_f < WELD || p.distance(to).to_f < WELD } }
          raise Error, 'граница переходного патча разорвана' unless arc
          arc.first.distance(from).to_f < WELD ? arc : arc.reverse
        end
        ab, ac, bc = curve.call(a,b), curve.call(a,c), curve.call(b,c)
        sample = lambda do |arc, t|
          index = t*n; i = index.floor.clamp(0,n); j = [i+1,n].min
          Geom.linear_combination(1-(index-i), arc[i], index-i, arc[j])
        end
        rows = (0..n).map do |i|
          (0..(n-i)).map do |j|
            u = (n-i-j).to_f/n; v = j.to_f/n; w = i.to_f/n
            point = Geom::Point3d.new(a.x*u+b.x*v+c.x*w, a.y*u+b.y*v+c.y*w, a.z*u+b.z*v+c.z*w)
            [[u,v,ab,a,b],[u,w,ac,a,c],[v,w,bc,b,c]].each do |x,y,arc,p,q|
              next if x+y < 1.0e-10
              t = y/(x+y); linear = Geom.linear_combination(1-t,p,t,q)
              delta = sample.call(arc,t)-linear
              point += Geom::Vector3d.new(delta.x*(x+y)**2,delta.y*(x+y)**2,delta.z*(x+y)**2)
            end
            point
          end
        end
        made = []
        (0...n).each do |i|
          top, bottom = rows[i], rows[i+1]
          (0...(top.length-1)).each do |j|
            triangles = [[top[j],top[j+1],bottom[j]]]
            triangles << [top[j+1],bottom[j+1],bottom[j]] if j < bottom.length-1
            triangles.each do |points|
              add_faces(entities, points).each do |face|
                seam = face.edges.find { |e| e.faces.length == 2 }
                if seam
                  other = (seam.faces-[face]).first
                  face.reverse! if seam.reversed_in?(face) == seam.reversed_in?(other)
                end
                face.material = patch[:front]; face.back_material = patch[:back]; face.layer = patch[:layer]
                face.set_attribute('BACommunity_BevelSurface', 'generated', true); made << face
              end
            end
          end
        end
        soften_all(made, smooth && n > 1); made
      end

      # Три угла патча — концы дуг, попарно совпадающие.
      def self.triangle_corners(arcs)
        ends = arcs.flat_map { |arc| [arc.first, arc.last] }
        corners = []
        ends.each do |point|
          next if corners.any? { |c| c.distance(point).to_f < WELD }
          corners << point
        end
        unless corners.length == 3
          raise Error, 'угол не сводится к сфере — узел пока не поддержан'
        end
        corners
      end

      # Лицо полосы смотрит прочь от оси дуги у выпуклого ребра и на неё —
      # у вогнутого: у вогнутого материал по другую сторону поверхности.
      def self.orient(face, info)
        mid = face.bounds.center
        out = GeomUtils.unit(mid - info.center_at(nearest_on_edge(info, mid)))
        return if out.nil?
        out = out.reverse unless info.convex?
        face.reverse! if face.normal.dot(out) < 0
      end

      # Швы между сегментами дуги сглаживаем, у прямой фаски (1 сегмент) — нет.
      def self.soften(quads, on)
        return unless on
        quads = quads.select(&:valid?)
        quads.each_cons(2) do |a, b|
          edge = (a.edges & b.edges).first
          next if edge.nil?
          edge.soft = true
          edge.smooth = true
        end
      end

      def self.soften_all(faces, on)
        return unless on
        faces = faces.select(&:valid?)
        faces.flat_map(&:edges).uniq.each do |edge|
          next unless edge.faces.length == 2
          next unless faces.include?(edge.faces[0]) && faces.include?(edge.faces[1])
          edge.soft = true
          edge.smooth = true
        end
      end

      # Грань по точкам. Четырёхугольники полосы плоские по построению (две
      # параллельные прямые), а вот клетки сферического патча лежат на сфере и
      # плоскими не бывают — такие режем веером на треугольники.
      def self.add_faces(entities, points)
        points = weld(points)
        return [] if points.length < 3
        begin
          face = entities.add_face(points)
          return face ? [face] : []
        rescue ArgumentError
          (1...(points.length - 1)).map do |i|
            begin
              entities.add_face(points[0], points[i], points[i + 1])
            rescue ArgumentError
              nil
            end
          end.compact.select(&:valid?)
        end
      end

      # Убираем совпавшие подряд точки: SketchUp на них ругается.
      def self.weld(points)
        out = []
        points.each do |point|
          out << point unless out.last && out.last.distance(point).to_f < WELD
        end
        out.pop if out.length > 1 && out.first.distance(out.last).to_f < WELD
        out
      end

    end # module Chamfer
  end # module BevelChamfer
end # module BACommunity
