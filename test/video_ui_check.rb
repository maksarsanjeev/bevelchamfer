raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
$bc_live_dialog.execute_script("sketchup.qa(JSON.stringify({height:innerHeight,scroll:document.documentElement.scrollHeight,width:innerWidth,size:document.getElementById('size').value,segments:document.getElementById('segments').value}));document.getElementById('seg-plus').click();")
