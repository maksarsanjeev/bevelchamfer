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

raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
bc_root = File.expand_path('..', __dir__)
%w[geom_utils chamfer_math chamfer modifier chamfer_panel].each do |file|
  load "#{bc_root}/src/bevelchamfer/#{file}.rb"
end
module BevelChamferRegression
  M = BACommunity::BevelChamfer
  MODEL = Sketchup.active_model
  def self.assert(condition, label)
    raise label unless condition
    puts "PASS #{label}"
  end
  def self.box
    group = MODEL.entities.add_group
    group.name = 'BC_REGRESSION'
    face = group.entities.add_face([0,0,0], [100,0,0], [100,100,0], [0,100,0])
    face.reverse! if face.normal.z < 0
    face.pushpull(60)
    group
  end
  def self.run
    groups = []
    begin
      rows = [[:pair,6,15,:radius,18,590286.152], [:rim,6,15,:radius,30,581263.466],
              [:corner,6,15,:radius,60,587473.701], [:all,6,15,:radius,366,552098.642],
              [:all,1,15,:offset,26,501000.000], [:one,4,20,:offset,10,590614.675],
              [:one,6,15,:radius,12,594970.286]]
      rows.each do |selection,n,size,mode,faces,volume|
        g = box; groups << g
        all = g.entities.grep(Sketchup::Edge)
        rim = all.select { |e| [e.start.position.z, e.end.position.z] == [60,60] }
        edges = case selection
        when :pair then rim.select { |e| [e.start.position,e.end.position].all? { |p| p.x==0 } || [e.start.position,e.end.position].all? { |p| p.y==0 } }
        when :rim then rim
        when :corner then all.select { |e| [e.start.position,e.end.position].include?(Geom::Point3d.new(0,0,60)) }
        when :all then all
        when :one then [rim.find { |e| e.start.position.y==0 && e.end.position.y==0 }]
        end
        M::Chamfer.apply(edges,size,n,mode:mode)
        assert(g.manifold? && g.entities.grep(Sketchup::Face).length==faces && (g.volume-volume).abs<0.001,
          "#{selection} n#{n}: solid, #{faces} faces, volume #{volume}")
      end
      g = MODEL.entities.add_group; groups << g
      f = g.entities.add_face([0,0,0],[100,0,0],[100,0,40],[50,0,40],[50,0,100],[0,0,100])
      f.reverse! if f.normal.y>0; f.pushpull(80)
      inner = g.entities.grep(Sketchup::Edge).find { |e| [e.start.position,e.end.position].all? { |p| p.x==50 && p.z==40 } }
      M::Chamfer.apply([inner],15,6,mode: :radius)
      assert(g.manifold? && (g.volume-564023.772).abs<0.001,'concave edge adds analytical volume')
      exact = 554303.086
      previous = 0
      [1,2,3,4,6,8,12,16,24].each do |n|
        g=box; groups << g
        M::Chamfer.apply(g.entities.grep(Sketchup::Edge),15,n,mode: :radius)
        assert(g.manifold? && g.volume>previous && g.volume<exact, "Steiner convergence n#{n}, volume #{g.volume.round(3)}")
        previous=g.volume
      end
      g=box;groups << g;all=g.entities.grep(Sketchup::Edge)
      one=all.find { |e| [e.start.position,e.end.position].all? { |p| p.y==0 && p.z==60 } }
      [[[one],49,true],[[one],60,false],[all,29,true],[all,31,false],[all,5000,false]].each do |edges,size,expect|
        okay = begin; M::Chamfer.plan(edges,size,6,:offset);true;rescue M::Chamfer::Error;false;end
        assert(okay==expect,"size limit #{edges.length} edges, #{size}: #{expect}")
      end
      [[Float::NAN,6,:offset],[15,0,:offset],[15,201,:offset],[15,6,:unknown]].each do |size,n,mode|
        rejected = begin; M::Chamfer.plan(all,size,n,mode);false;rescue M::Chamfer::Error;true;end
        assert(rejected,'invalid parameters rejected')
      end
      puts 'LIVE_SU2024_REGRESSION_OK'
    ensure
      MODEL.start_operation('Cleanup bevelchamfer regression',true)
      groups.each { |g| g.erase! if g.valid? }
      MODEL.commit_operation
    end
  end
end
BevelChamferRegression.run
