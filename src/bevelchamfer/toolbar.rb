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

# Оформление плагина: панель инструментов и меню.
# Считает chamfer.rb, окно и превью — chamfer_panel.rb.
module BACommunity
  module BevelChamfer

    TOOLBAR_NAME = 'bevelchamfer'.freeze
    MENU_NAME    = 'bevelchamfer'.freeze
    ICONS_DIR    = File.join(File.dirname(__FILE__), 'icons').freeze

    BUTTONS = [
      {
        icon:    'chamfer',
        title:   'Фаска и скругление',
        tooltip: 'Фаска и скругление рёбер',
        status:  'Выделите рёбра (или группу целиком): размер, число сегментов, 1 сегмент — прямая фаска',
        action:  -> { ChamferPanel.show }
      }
    ].freeze

    # Пара путей [большая иконка, маленькая]. SVG понимает только
    # Windows-версия SketchUp (2016+), macOS вместо него требует PDF —
    # поэтому там откатываемся на PNG.
    def self.icon_paths(name)
      svg = File.join(ICONS_DIR, "#{name}.svg")
      if Sketchup.platform == :platform_win && File.exist?(svg)
        [svg, svg]
      else
        [File.join(ICONS_DIR, "#{name}_24.png"), File.join(ICONS_DIR, "#{name}_16.png")]
      end
    end

    def self.build_command(spec)
      cmd = UI::Command.new(spec[:title]) { spec[:action].call }

      large_icon, small_icon = icon_paths(spec[:icon])
      # Иконку ставим только если файл на месте: иначе SketchUp ругается,
      # а кнопка и без картинки останется рабочей.
      cmd.large_icon = large_icon if File.exist?(large_icon)
      cmd.small_icon = small_icon if File.exist?(small_icon)

      cmd.tooltip         = spec[:tooltip]
      cmd.status_bar_text = spec[:status]
      cmd
    end

    def self.create_toolbar
      toolbar = UI::Toolbar.new(TOOLBAR_NAME)
      BUTTONS.each { |spec| toolbar.add_item(build_command(spec)) }

      # Первый запуск — показываем панель, дальше уважаем выбор пользователя.
      if toolbar.get_last_state == TB_NEVER_SHOWN
        toolbar.show
      else
        toolbar.restore
      end
      toolbar
    end

    def self.create_menu
      menu = UI.menu('Extensions').add_submenu(MENU_NAME)
      BUTTONS.each { |spec| menu.add_item(spec[:title]) { spec[:action].call } }
      menu
    end

  end # module BevelChamfer
end # module BACommunity
