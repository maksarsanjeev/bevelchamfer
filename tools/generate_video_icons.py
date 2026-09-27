"""Copyright 2026 B&A community. Apache-2.0. Native vector icon assets."""
from pathlib import Path
from shutil import copyfile
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parent.parent
source = root / 'design/icon-03-refined'
out = root / 'src/bevelchamfer/icons'
copyfile(source / 'bevelchamfer-toolbar.svg', out / 'chamfer.svg')
for size in (16, 24):
    copyfile(source / f'bevelchamfer-{size}.png', out / f'chamfer_{size}.png')
symbols = {
 'interactive': '<path d="M17 15 L17 22 L19 20 L21 23 L22 22 L20 19 L23 19 Z" fill="white" stroke="#263c57" stroke-width=".6"/>',
 'live': '<path d="M17 18 A3 3 0 1 1 18 22 M16 17 L17 20 L20 18" fill="none" stroke="white" stroke-width="1.3"/>',
 'soften': '<path d="M16 22 Q17 16 22 16" fill="none" stroke="white" stroke-width="1.4"/><circle cx="20" cy="21" r=".8" fill="white"/><circle cx="22" cy="19" r=".8" fill="white"/>',
 'clean': '<path d="M16 20 L20 16 L23 19 L20 22 L18 22 Z" fill="white" stroke="#263c57" stroke-width=".5"/><path d="M18 18 L21 21" stroke="#347BBE"/>',
 'settings': '<path d="M19.5 15 V23 M15.5 19 H23.5 M16.5 16 L22.5 22 M16.5 22 L22.5 16" stroke="white" stroke-width="2"/><circle cx="19.5" cy="19" r="3" fill="white"/><circle cx="19.5" cy="19" r="1.4" fill="#347BBE"/>'
}
base = (out / 'chamfer.svg').read_text(encoding='utf-8')
for name, symbol in symbols.items():
    svg = base.replace('</svg>', '<circle cx="19.5" cy="19" r="5" fill="#347BBE" stroke="white" stroke-width=".5"/>' + symbol + '</svg>')
    (out / f'{name}.svg').write_text(svg, encoding='utf-8')
    for size in (16, 24):
        im = Image.open(source / f'bevelchamfer-{size}.png').convert('RGBA').resize((size*4,size*4))
        d = ImageDraw.Draw(im); s = size*4/24
        def line(points, width=1.4): d.line([(x*s,y*s) for x,y in points], fill='white',width=max(1,round(width*s)))
        d.ellipse((14.5*s,14*s,24*s,24*s), fill='#347BBE',outline='white',width=max(1,round(s*.5)))
        if name=='interactive': d.polygon([(x*s,y*s) for x,y in [(17,15),(17,22),(19,20),(21,23),(22,22),(20,19),(23,19)]],fill='white')
        elif name=='live':
            d.arc((16*s,16*s,23*s,23*s),30,330,fill='white',width=round(s*1.3));line([(16,16),(17,19),(20,17)])
        elif name=='soften':
            line([(16,22),(17,19),(19,17),(22,16)]); d.ellipse((19*s,20*s,21*s,22*s),fill='white')
        elif name=='clean':
            d.polygon([(x*s,y*s) for x,y in [(16,20),(20,16),(23,19),(20,22),(18,22)]],fill='white');line([(18,18),(21,21)],.6)
        else:
            for a,b in [((19.5,15),(19.5,23)),((15.5,19),(23.5,19)),((16.5,16),(22.5,22)),((16.5,22),(22.5,16))]:line([a,b],2)
            d.ellipse((17*s,16.5*s,22*s,21.5*s),fill='white');d.ellipse((18.2*s,17.7*s,20.8*s,20.3*s),fill='#347BBE')
        im.resize((size,size),Image.Resampling.LANCZOS).save(out / f'{name}_{size}.png')
