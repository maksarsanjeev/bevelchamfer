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

    HERE = File.dirname(__FILE__).freeze

    # Порядок важен: geom_utils нужен математике фаски, та — движку.
    require File.join(HERE, 'geom_utils.rb')
    require File.join(HERE, 'chamfer_math.rb')
    require File.join(HERE, 'chamfer.rb')
    require File.join(HERE, 'modifier.rb')
    require File.join(HERE, 'chamfer_panel.rb')
    require File.join(HERE, 'toolbar.rb')

    unless @interface_created || file_loaded?(__FILE__)
      create_menu
      @toolbar = create_toolbar

      file_loaded(__FILE__)
    end
    @interface_created = true

  end # module BevelChamfer
end # module BACommunity
