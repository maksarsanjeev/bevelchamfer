raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b = BACommunity::BevelChamfer
begin
  values = b::LiveBevel.data($bc_recheck_group)
  result = b::LiveBevel.parts($bc_recheck_group).last
  raise 'Opacity UI did not apply 56 percent' unless $bc_recheck_qa['step'] == '0.01' && values['opacity'] == 0.56 && result.entities.grep(Sketchup::Face).all? { |face| (face.material.alpha - 0.56).abs < 0.01 }
  puts 'PASS native Live HTML slider applies 56 percent with one-percent precision'
ensure
  b::LivePanel.close
  $bc_recheck_group.erase! if $bc_recheck_group&.valid?
  m = Sketchup.active_model; m.selection.clear
  $bc_recheck_selection.each { |item| m.selection.add(item) if item.valid? }
  b::MeshTools.save($bc_recheck_preferences)
end
