raise 'Only SketchUp 2024' unless Sketchup.version.to_i == 24
$bc_recheck_dialog.execute_script("const opacity=document.getElementById('opacity');opacity.value='0.56';opacity.dispatchEvent(new Event('input'));opacity.dispatchEvent(new Event('change'));sketchup.qa(JSON.stringify({step:opacity.step,value:opacity.value}));")
