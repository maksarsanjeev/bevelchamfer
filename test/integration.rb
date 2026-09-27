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
load File.join(bc_root, 'src/bevelchamfer/main.rb')
%w[geom_utils chamfer_math chamfer modifier chamfer_panel].each { |f| load "#{bc_root}/src/bevelchamfer/#{f}.rb" }
module BevelChamferLiveTest
  M = BACommunity::BevelChamfer
  MODEL = Sketchup.active_model
  def self.assert(condition, message)
    raise message unless condition
    puts "PASS #{message}"
  end
  def self.box
    g = MODEL.entities.add_group
    g.name = 'BC_LIVE_TEST'
    f = g.entities.add_face([0,0,0], [100,0,0], [100,100,0], [0,100,0])
    f.reverse! if f.normal.z < 0
    f.pushpull(60)
    g
  end
  def self.run
    groups = []
    original_selection = MODEL.selection.to_a
    begin
      g = box; groups << g
      source_material = MODEL.materials.add('BC_SOURCE_MAT')
      source_material.color = 'blue'
      g.entities.grep(Sketchup::Face).each { |f| f.material = source_material; f.back_material = source_material }
      edges = g.entities.grep(Sketchup::Edge)
      M::Modifier.apply(g, edges, 15.0, 6, :radius)
      assert(g.manifold? && (g.volume-552098.642).abs < 0.001, 'modifier first build analytic volume')
      assert(g.entities.grep(Sketchup::Face).all? { |f| f.material == source_material && f.back_material == source_material }, 'materials retained on faces strips and corner patches')
      assert(M::Modifier.data(g)['source']['faces'].length == 6, 'source retained in attribute')
      M::Modifier.apply(g, [], 10.0, 4, :offset)
      assert(g.manifold? && g.entities.grep(Sketchup::Face).length == 182, 'modifier regenerate from original')
      wrapper = MODEL.entities.add_group; groups << wrapper
      stored = wrapper.entities.add_instance(g.definition, Geom::Transformation.new)
      stored.set_attribute(M::Modifier::KEY, 'data', g.get_attribute(M::Modifier::KEY, 'data'))
      require 'fileutils'
      path = File.expand_path('../build/roundtrip.skp', __dir__)
      FileUtils.mkdir_p(File.dirname(path))
      raise 'save SKP failed' unless wrapper.definition.save_as(path)
      loaded = MODEL.definitions.load(path)
      persisted = loaded.entities.find { |e| e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group) }
      assert(persisted && M::Modifier.data(persisted)['source']['faces'].length == 6, 'source and parameters survive SKP serialization')
      M::Modifier.apply(persisted, [], 12, 6, :radius)
      assert(persisted.manifold? && M::Modifier.data(persisted)['size'] == 12, 'modifier editable after loading SKP')
      sig = M::Modifier.signature(g)
      lines = M::Modifier.preview(g, 8.0, 8, :radius)
      assert(lines.length > 0 && M::Modifier.signature(g) == sig, 'preview leaves mesh unchanged')
      previous = g.get_attribute(M::Modifier::KEY, 'data')
      begin
        M::Modifier.apply(g, [], 5000, 8, :offset)
        raise 'oversize accepted'
      rescue M::Chamfer::Error
        assert(M::Modifier.signature(g) == sig && g.get_attribute(M::Modifier::KEY, 'data') == previous, 'invalid modifier rolls back mesh and attributes')
      end
      material = MODEL.materials.add('BC_LIVE_TEST_MAT')
      material.color = 'red'
      g.entities.grep(Sketchup::Face).first.material = material
      modified_sig = M::Modifier.signature(g)
      begin
        M::Modifier.apply(g, [], 15, 6, :radius)
        raise 'manual edits overwritten'
      rescue M::Chamfer::Error
        assert(M::Modifier.signature(g) == modified_sig, 'manual changes protected')
      end
      M::Modifier.bake(g)
      assert(!M::Modifier.data(g) && M::Modifier.signature(g) == modified_sig, 'bake retains manual changes')
      g2 = box; groups << g2
      component = g2.to_component; groups[-1] = component
      sibling = MODEL.entities.add_instance(component.definition, Geom::Transformation.translation([150,0,0])); groups << sibling
      M::Modifier.apply(component, component.definition.entities.grep(Sketchup::Edge), 15, 6, :radius)
      assert(component.definition != sibling.definition && sibling.definition.entities.grep(Sketchup::Face).length == 6, 'component sibling unchanged')
      MODEL.selection.clear; MODEL.selection.add(component)
      M::ChamferPanel.run_apply(254, 4, :offset, parametric: true)
      assert(M::Modifier.data(component)['segments'] == 4 && (M::Modifier.data(component)['size'] - 10).abs < 1e-8, 'panel updates saved modifier')
      component.transformation = Geom::Transformation.translation([250, 50, 20]) * Geom::Transformation.scaling(2)
      assert((M::ChamferPanel.local_size(254) - 5).abs < 1e-8, 'uniform scale respects world millimeters')
      M::ChamferPanel.run_preview(254, 8, :radius)
      current = M::ChamferPreview.instance_variable_get(:@current)
      assert(current && current.active? && current.lines.flatten.all? { |p| p.x > 200 }, 'preview transformed into model coordinates')
      M::ChamferPreview.stop
      component.transformation = Geom::Transformation.scaling(2, 1, 1)
      begin
        M::ChamferPanel.local_size(20)
        raise 'nonuniform scale accepted'
      rescue M::Chamfer::Error
        puts 'PASS nonuniform scale rejected before edits'
      end
      MODEL.selection.clear
      M::ChamferPanel.run_preview(20, 8, :offset)
      assert(!current.active?, 'empty selection clears preview')
      puts 'LIVE_SU2024_INTEGRATION_OK'
    ensure
      M::ChamferPreview.stop
      MODEL.start_operation('Cleanup bevelchamfer tests', true)
      groups.each { |x| x.erase! if x.valid? }
      MODEL.materials.remove(material) if material
      MODEL.definitions.remove(loaded) if loaded && loaded.valid? && loaded.instances.empty?
      MODEL.materials.remove(source_material) if source_material
      MODEL.commit_operation
      MODEL.selection.clear
      MODEL.selection.add(original_selection.select(&:valid?))
    end
  end
end
BevelChamferLiveTest.run
