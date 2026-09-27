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
%w[geom_utils chamfer_math chamfer modifier].each { |f| load "#{bc_root}/src/bevelchamfer/#{f}.rb" }
model=Sketchup.active_model
mesh=model.entities.add_group
begin
  e=mesh.entities
  face=e.add_face([0,0,0],[100,0,0],[100,100,0],[0,100,0])
  hole=e.add_face([30,30,0],[70,30,0],[70,70,0],[30,70,0]);hole.erase!
  face=e.grep(Sketchup::Face).first
  face.reverse! if face.normal.z<0;face.pushpull(60)
  raise 'annular solid setup failed' unless mesh.manifold? && (mesh.volume-504000).abs<0.001
  m=BACommunity::BevelChamfer
  source=m::Modifier.snapshot(mesh)
  signature=m::Modifier.signature(mesh)
  model.start_operation('Snapshot roundtrip test',true)
  m::Modifier.restore(e,source)
  model.commit_operation
  raise 'hole lost during snapshot restoration' unless mesh.manifold? && (mesh.volume-504000).abs<0.001 && m::Modifier.signature(mesh)==signature
  puts 'PASS source restoration preserves holes and volume'
  edge=e.grep(Sketchup::Edge).find { |x| [x.start.position,x.end.position].all? { |p| p.y==0 && p.z==60 } }
  m::Modifier.apply(mesh,[edge],10,6,:radius)
  raise 'hole lost during chamfer' unless mesh.manifold? && mesh.entities.grep(Sketchup::Face).any? { |f| f.loops.length==2 }
  puts 'PASS chamfer preserves holes and closed solid'
ensure
  mesh.erase! if mesh.valid?
end
