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

# bevelchamfer — гладкая геометрия для SketchUp: фаска и скругление.
# Точка входа: регистрирует расширение, реальный код грузится из
# bevelchamfer/main.rb.

require 'sketchup.rb'
require 'extensions.rb'

module BACommunity
  module BevelChamfer

    EXTENSION_NAME = 'bevelchamfer'.freeze
    VERSION        = '0.1.1'.freeze

    loader = SketchupExtension.new(EXTENSION_NAME, File.join('bevelchamfer', 'main.rb'))
    loader.copyright   = 'Copyright 2026 B&A community, Apache License 2.0'
    loader.creator     = 'B&A community — maksarsanjeev, Royalb21'
    loader.version     = VERSION
    loader.description = 'Фаска и скругление рёбер с честной сшивкой углов, ' \
                         'с изменяемыми параметрами. SketchUp 2024–2026.'
    Sketchup.register_extension(loader, true)

  end # module BevelChamfer
end # module BACommunity
