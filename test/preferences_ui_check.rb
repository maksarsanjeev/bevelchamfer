raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b=BACommunity::BevelChamfer
begin
 raise 'Preferences change failed' unless b::MeshTools.settings['angle']==15 && b::MeshTools.settings['language']=='en'
 raise 'Preferences UI overflow or translation failed' unless $bc_prefs_qa && $bc_prefs_qa['height'] >= $bc_prefs_qa['scroll'] && $bc_prefs_qa['heading']=='Soften edges'
 puts 'PASS real Preferences HtmlDialog angle, language and no overflow'
ensure
 b::MeshTools.save($bc_prefs_before);$bc_prefs_dialog.close
end
