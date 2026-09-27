raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
b = BACommunity::BevelChamfer; m = Sketchup.active_model
raise 'Live UI overflow' unless $bc_live_ui && $bc_live_ui['scroll'] <= $bc_live_ui['height']
raise 'Live UI button did not work' unless b::LiveBevel.data($bc_ui_group)['segments'] == 9
puts 'PASS live HtmlDialog fits and segments button regenerates geometry'
m.active_path = [$bc_ui_group]
puts 'Native double-click equivalent: enter group pending automatic proxy entry'
