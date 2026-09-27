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

    # Мелкая векторная математика, общая для фаски и кривых.
    # Всё во внутренних единицах SketchUp (дюймы).
    module GeomUtils

      # Допуск самого SketchUp — 0.001". Точки ближе этого он склеит сам,
      # поэтому ниже него не опускаемся: считать точнее бессмысленно.
      TOL      = 0.001
      # Допуск для направлений и синусов углов — здесь речь о числах
      # порядка единицы, а не о длинах, поэтому он куда мельче.
      EPS      = 1.0e-9

      module_function

      def unit(vec)
        v = vec.clone
        return nil if v.length.to_f < EPS
        v.normalize!
        v
      end

      # Точка + вектор * длина. Просто чтобы не писать offset там,
      # где длина может оказаться нулевой (offset на нуле бросает исключение).
      def along(point, vec, dist)
        return point.clone if dist.to_f.abs < EPS
        point.offset(vec, dist)
      end

      # Пересечение прямой с плоскостью. line = [точка, направление],
      # plane = [точка, нормаль]. nil, если прямая плоскости параллельна.
      def line_plane(line, plane)
        denom = line[1].dot(plane[1])
        return nil if denom.abs < EPS
        Geom.intersect_line_plane(line, [plane[0], plane[1]])
      end

      # Пересечение двух прямых, заданных точкой и направлением.
      # nil для параллельных и скрещивающихся.
      def line_line(p1, d1, p2, d2)
        Geom.intersect_line_line([p1, d1], [p2, d2])
      end

      # Сферическая интерполяция между двумя векторами одной длины:
      # даёт дугу окружности, не трогая знаки поворота и оси. Именно это
      # нам и нужно — направление обхода задаётся самими концами.
      def slerp(v0, v1, t)
        omega = v0.angle_between(v1)
        if omega < EPS
          # Векторы совпали: интерполировать нечего.
          return v0.clone
        end
        if (Math::PI - omega).abs < EPS
          # Развёрнуты на 180°: плоскость дуги неопределена, звать сюда нельзя.
          raise ArgumentError, 'slerp: векторы противоположны, дуга неоднозначна'
        end
        s = Math.sin(omega)
        a = Math.sin((1.0 - t) * omega) / s
        b = Math.sin(t * omega) / s
        Geom::Vector3d.new(v0.x * a + v1.x * b,
                           v0.y * a + v1.y * b,
                           v0.z * a + v1.z * b)
      end

      # Дуга из segments отрезков между двумя точками окружности с центром
      # center. segments = 1 даёт хорду — это и есть прямая фаска.
      def arc_points(center, from, to, segments)
        v0 = from - center
        v1 = to - center
        return [from.clone, to.clone] if segments <= 1
        (0..segments).map do |i|
          t = i.to_f / segments
          center + slerp(v0, v1, t)
        end
      end

      # Направление внутрь грани: перпендикуляр к ребру, лежащий в плоскости
      # грани. Считаем по обходу петли, а не по центру габарита: петля всегда
      # обходит грань против часовой вокруг нормали, поэтому normal x обход
      # смотрит строго внутрь — даже у вогнутых и дырявых граней.
      def inward_perp(face, edge)
        dir = unit(edge.end.position - edge.start.position)
        return nil if dir.nil?
        dir = dir.reverse if edge.reversed_in?(face)
        unit(face.normal.cross(dir))
      end

      # Плоскость грани в виде [точка, нормаль].
      def face_plane(face)
        [face.vertices.first.position, face.normal]
      end

    end # module GeomUtils
  end # module BevelChamfer
end # module BACommunity
