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

module BACommunity
  module BevelChamfer

    # Окно фаски: что выделено, каким размером резать, сколько сегментов.
    # Считать умеет chamfer.rb, здесь только разговор с человеком.
    module ChamferPanel

      HTML_FILE = File.join(File.dirname(__FILE__), 'html', 'chamfer.html').freeze

      @dialog = nil

      def self.show
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          push
          return @dialog
        end

        @dialog = UI::HtmlDialog.new(
          dialog_title:    'bevelchamfer — фаска и скругление',
          preferences_key: 'BACommunity_BevelChamfer_Compact',
          scrollable:      false,
          resizable:       true,
          width:           400,
          height:          250,
          min_width:       340,
          min_height:      240,
          style:           UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_file(HTML_FILE)
        attach(@dialog)
        # Закрыли окно — превью во вьюпорте больше нечем управлять, убираем.
        @dialog.set_on_closed { ChamferPreview.stop }
        @dialog.show
        @dialog
      end

      def self.attach(dialog)
        dialog.add_action_callback('ready') { |_ctx| push }
        dialog.add_action_callback('close') { |_ctx| dialog.close }
        dialog.add_action_callback('refresh') { |_ctx| push }
        dialog.add_action_callback('bake') { |_ctx| run_bake }
        dialog.add_action_callback('stop') { |_ctx| ChamferPreview.stop; preview_state(false) }
        dialog.add_action_callback('preview') do |_ctx, size, segments, mode|
          run_preview(size.to_f, segments.to_i, mode.to_s.to_sym)
        end
        # Живое превью со слайдеров: то же самое, но без отчёта на каждый тик.
        dialog.add_action_callback('live') do |_ctx, size, segments, mode|
          run_preview(size.to_f, segments.to_i, mode.to_s.to_sym, quiet: true)
        end
        dialog.add_action_callback('apply') do |_ctx, size, segments, mode, parametric|
          run_apply(size.to_f, segments.to_i, mode.to_s.to_sym, parametric: parametric == true)
        end
      end

      # --- что выделено ------------------------------------------------------

      # Рёбра берём из выделения. Выделили группу или компонент — берём все
      # рёбра внутри: так «скруглить всю коробку» делается одним кликом.
      # Негодные рёбра здесь не отсеиваем: это работа движка, он же объяснит.
      def self.selected_edges
        selection = Sketchup.active_model.selection
        edges = selection.grep(Sketchup::Edge) + selection.grep(Sketchup::Face).flat_map(&:edges)
        selection.each do |entity|
          case entity
          when Sketchup::Group             then edges.concat(entity.entities.grep(Sketchup::Edge))
          when Sketchup::ComponentInstance then edges.concat(entity.definition.entities.grep(Sketchup::Edge))
          end
        end
        edges.uniq.select { |edge| edge.faces.length == 2 }
      end

      def self.selected_object
        selected = Sketchup.active_model.selection.to_a
        return nil unless selected.length == 1
        object = selected.first
        object if object.is_a?(Sketchup::Group) || object.is_a?(Sketchup::ComponentInstance)
      end

      def self.transform
        model = Sketchup.active_model
        object = selected_object
        object ? model.edit_transform * object.transformation : model.edit_transform
      end

      def self.local_size(size)
        t = transform
        axes = [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, 0, 1)].map { |a| a.transform(t) }
        scales = axes.map { |a| a.length.to_f }
        unless scales.min > 1e-9 && scales.max - scales.min < 1e-6 &&
               axes.combination(2).all? { |a, b| a.dot(b).abs < 1e-6 * a.length.to_f * b.length.to_f }
          raise Chamfer::Error, 'Объект растянут неодинаково по осям. Сначала сбросьте масштаб объекта.'
        end
        size.mm / scales.first
      end

      def self.run_bake
        object = selected_object
        raise Chamfer::Error, 'Выделите объект с параметрической фаской.' unless object && Modifier.data(object)
        ChamferPreview.stop
        Modifier.bake(object)
        push
        say('Фаска запечена. Исходник удалён, геометрия сохранена. Ctrl+Z отменяет.', 'ok')
      rescue StandardError => e
        say(e.message, 'warn')
      end

      def self.push
        edges = selected_edges
        @dialog&.execute_script("app.state(#{JSON.generate(
          edges: edges.length,
          units: unit_name,
          modifier: selected_object && Modifier.data(selected_object),
          scale: Geom::Vector3d.new(1, 0, 0).transform(transform).length.to_f,
          object: !selected_object.nil?
        )})")
      end

      def self.preview_state(active)
        @dialog&.execute_script("app.preview(#{active ? 'true' : 'false'})")
      end

      def self.say(text, kind = 'info')
        @dialog&.execute_script("app.say(#{JSON.generate(text)}, #{JSON.generate(kind)})")
      end

      def self.unit_name
        'мм'
      end

      # --- действия ----------------------------------------------------------

      def self.gather(size, segments)
        edges = selected_edges
        if edges.empty?
          say('Выделите рёбра, группу или компонент — и нажмите «Обновить».', 'warn')
          return nil
        end
        if !size.finite? || size <= 0
          say('Размер должен быть больше нуля.', 'warn')
          return nil
        end
        if segments < 1 || segments > 200
          say('Сегментов: от 1 до 200.', 'warn')
          return nil
        end
        parents = edges.map { |edge| edge.parent }.uniq
        if parents.length > 1
          say('Рёбра из разных групп сразу не обработать — выделите что-то одно.', 'warn')
          return nil
        end
        object = selected_object
        raise Chamfer::Error, 'Объект заблокирован.' if object && object.locked?
        parent = Sketchup.active_model.active_path&.last
        if !object && parent && parent.definition.instances.length > 1
          raise Chamfer::Error, 'Выделите экземпляр снаружи: плагин создаст для него уникальную копию.'
        end
        edges
      end

      def self.run_preview(size, segments, mode, quiet: false)
        edges = gather(size, segments)
        if edges.nil?
          preview_state(false)
          ChamferPreview.stop
          return
        end
        object = selected_object
        saved = object && Modifier.data(object)
        if saved
          lines = Modifier.preview(object, local_size(size), segments, mode)
          notes = {}
          count = saved['edges'].length
          patches = 0
        else
          plan = Chamfer.plan(edges, local_size(size), segments, mode)
          lines = Chamfer.preview_lines(plan)
          notes = plan.notes
          count = plan.infos.length
          patches = plan.patches.length
        end
        t = transform
        ChamferPreview.show(lines.map { |line| line.map { |point| point.transform(t) } })
        return if quiet && notes.empty?
        say("Показано: рёбер #{count}, узлов со сшивкой #{patches}. " \
            "#{notes_text(notes)}Enter — применить, Esc — убрать превью.")
      rescue StandardError => e
        ChamferPreview.stop
        preview_state(false)
        say(e.message, 'warn')
      end

      def self.run_apply(size, segments, mode, parametric: false)
        ChamferPreview.stop
        preview_state(false)
        edges = gather(size, segments)
        return if edges.nil?
        ChamferPreview.stop
        object = selected_object
        amount = local_size(size)
        if object && (parametric || Modifier.data(object))
          result = Modifier.apply(object, edges, amount, segments, mode)
        elsif object
          model = Sketchup.active_model
          model.start_operation('bevelchamfer — фаска', true)
          begin
            keys = edges.map { |e| Modifier.edge_key(e) }
            object.make_unique
            result = Chamfer.apply(Modifier.matching(Modifier.entities(object), keys), amount, segments, mode: mode, operation: false)
            model.commit_operation
          rescue StandardError
            model.abort_operation
            raise
          end
        else
          result = Chamfer.apply(edges, amount, segments, mode: mode)
        end
        say("Готово: рёбер #{result.edges}, новых граней #{result.faces}. " \
            "#{notes_text(result.notes)}Отменяется через Ctrl+Z.", 'ok')
        push
      rescue StandardError => e
        say(e.message, 'warn')
      end

      def self.notes_text(notes)
        return '' if notes.nil? || notes.empty?
        notes.map { |message, count| "Пропущено #{count}: #{message}." }.join(' ') + ' '
      end

    end # module ChamferPanel

    # Превью во вьюпорте. Ничего не строит — только рисует то, что посчитал
    # план, поэтому его можно гонять сколько угодно и без отмены. Пока
    # крутят слайдеры, план пересчитывается на каждый тик и инструмент просто
    # подменяет себе линии — без переактивации, иначе SketchUp моргал бы
    # статусной строкой и курсором.
    class ChamferPreview

      # Синий акцент B&A community, как в панели.
      COLOR = Sketchup::Color.new(43, 108, 176)

      @current = nil

      def self.show(lines)
        if @current&.active?
          @current.lines = lines
          Sketchup.active_model.active_view.invalidate
        else
          @current = new(lines)
          Sketchup.active_model.select_tool(@current)
        end
      end

      # Снимаем только собственный инструмент: если пользователь уже
      # переключился на что-то своё, трогать его выбор нельзя.
      def self.stop
        return unless @current&.active?
        Sketchup.active_model.select_tool(nil)
      end

      attr_accessor :lines

      def initialize(lines)
        @lines = lines
        @active = false
      end

      def active?
        @active
      end

      def activate
        @active = true
        Sketchup.status_text = 'Превью фаски. Enter в окне — применить, Esc — убрать.'
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        @active = false
        ChamferPanel.preview_state(false)
        Sketchup.status_text = ''
        view.invalidate
      end

      def resume(view)
        view.invalidate
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        view.line_width = 2
        view.drawing_color = COLOR
        @lines.each { |line| view.draw(GL_LINE_STRIP, line) if line.length > 1 }
      end

      def getExtents
        bounds = Geom::BoundingBox.new
        @lines.each { |line| line.each { |point| bounds.add(point) } }
        bounds
      end

    end # class ChamferPreview
  end # module BevelChamfer
end # module BACommunity
