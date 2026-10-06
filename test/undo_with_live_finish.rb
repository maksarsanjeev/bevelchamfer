raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
begin
  load File.join(__dir__, 'undo_plain_group_finish.rb')
  puts 'PASS ordinary group Undo unaffected by unrelated Live object'
ensure
  m = Sketchup.active_model
  m.active_path = nil if m.active_path
  $bc_undo_background_live.erase! if $bc_undo_background_live&.valid?
end
