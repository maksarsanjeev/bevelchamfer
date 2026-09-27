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

    # Математика фаски. Здесь только счёт: ни одна функция этого файла
    # ничего в модели не меняет. Геометрию строит chamfer.rb по готовому плану.
    #
    # Соглашения:
    #   u1, u2 — единичные векторы от ребра внутрь каждой из двух смежных
    #            граней, перпендикулярно ребру;
    #   phi    — угол между ними (0..pi). Для выпуклого ребра коробки phi = 90°,
    #            для вогнутого «внутреннего угла» — тоже 90°: выпуклость на
    #            саму дугу не влияет, меняется лишь по какую сторону от ребра
    #            окажется центр (внутри материала или в пустоте), а это
    #            получается само собой;
    #   d      — отступ точки касания от ребра по каждой грани, r / tan(phi/2);
    #   cdist  — расстояние от ребра до центра дуги по биссектрисе, r / sin(phi/2).
    module ChamferMath

      # Ребро с почти нулевым углом («лезвие») развернуло бы отступ в
      # бесконечность, почти развёрнутое (плоскость) — скруглять нечего.
      MIN_ANGLE = 2.0 * Math::PI / 180.0    # 2°
      MAX_ANGLE = Math::PI - MIN_ANGLE

      # Разобранное ребро: вся геометрия профиля считается один раз здесь.
      class EdgeInfo

        attr_reader :edge, :a, :b, :dir, :f1, :f2, :u1, :u2,
                    :phi, :radius, :offset, :segments,
                    :f1_material, :f1_back_material, :f1_layer

        # mode: :radius — задан радиус, :offset — задан катет фаски.
        # Катет удобнее архитектору («фаска 20 мм»), радиус — геометру;
        # внутри всё равно живём радиусом.
        def initialize(edge, size, segments, mode)
          @edge     = edge
          @segments = [segments.to_i, 1].max

          faces = edge.faces
          raise Error, "у ребра #{faces.length} гран(и) вместо двух" unless faces.length == 2
          @f1, @f2 = faces

          @a = edge.start.position
          @b = edge.end.position
          @dir = GeomUtils.unit(@b - @a)
          raise Error, 'ребро нулевой длины' if @dir.nil?

          @u1 = GeomUtils.inward_perp(@f1, edge)
          @u2 = GeomUtils.inward_perp(@f2, edge)
          raise Error, 'не удалось построить нормаль в плоскости грани' if @u1.nil? || @u2.nil?

          @phi = @u1.angle_between(@u2)
          raise Error, 'грани почти совпали по направлению' if @phi < MIN_ANGLE
          raise Error, 'грани почти в одной плоскости — скруглять нечего' if @phi > MAX_ANGLE

          half = @phi / 2.0
          if mode == :offset
            @offset = size.to_f
            @radius = @offset * Math.tan(half)
          else
            @radius = size.to_f
            @offset = @radius / Math.tan(half)
          end
          @cdist = @radius / Math.sin(half)
          @bis   = GeomUtils.unit(Geom::Vector3d.new(@u1.x + @u2.x, @u1.y + @u2.y, @u1.z + @u2.z))

          # Выпуклое ребро или вогнутое: у выпуклого нормаль одной грани смотрит
          # прочь от другой. Отличать надо только ради стороны новых граней —
          # на саму дугу выпуклость не влияет.
          @convex = @f1.normal.dot(@u2) < 0

          # Материалы забираем сразу: к моменту сборки прежние грани уже снесены.
          @f1_layer = @f1.layer
          @f1_material      = @f1.material
          @f1_back_material = @f1.back_material
        end

        def convex?
          @convex
        end

        def length
          @a.distance(@b)
        end

        # Центр дуги в сечении, проведённом через точку pt.
        def center_at(pt)
          GeomUtils.along(pt, @bis, @cdist)
        end

        # Точки профиля в сечении через pt: от касания на f1 к касанию на f2.
        # segments = 1 даёт две точки — это и есть прямая фаска.
        def profile_at(pt)
          from = GeomUtils.along(pt, @u1, @offset)
          to   = GeomUtils.along(pt, @u2, @offset)
          GeomUtils.arc_points(center_at(pt), from, to, @segments)
        end

        # Опорный профиль в начале ребра. Индекс 0 — касание на f1, последний — на f2.
        def profile
          @profile ||= profile_at(@a)
        end

        # «Рельс» — прямая, вдоль которой едет i-я точка профиля.
        def rail(index)
          [profile[index], @dir]
        end

        def rail_count
          @segments + 1
        end

        # Профиль, развёрнутый так, чтобы индекс 0 лежал на грани face.
        def profile_from(face)
          face == @f1 ? profile : profile.reverse
        end

        def other_face(face)
          face == @f1 ? @f2 : @f1
        end

        def has_face?(face)
          face == @f1 || face == @f2
        end

        # Направление ребра, уводящее прочь от вершины v.
        def direction_from(vertex)
          vertex.position == @a ? @dir : @dir.reverse
        end

        # Линия отступа на грани face: по ней пройдёт новая кромка грани.
        def offset_line(face)
          u = (face == @f1 ? @u1 : @u2)
          [GeomUtils.along(@a, u, @offset), @dir]
        end

        # Точка касания на грани face в сечении через pt.
        def tangent_on(face, pt)
          GeomUtils.along(pt, face == @f1 ? @u1 : @u2, @offset)
        end

      end # class EdgeInfo

      # Ошибка расчёта: текст уходит пользователю как есть, без backtrace.
      class Error < StandardError; end

    end # module ChamferMath
  end # module BevelChamfer
end # module BACommunity
