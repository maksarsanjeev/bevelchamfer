# Copyright 2026 B&A community. Apache License 2.0.
# Изометрическая схема куба: три грани и синий пояс фасок.
from pathlib import Path
from math import sqrt
from itertools import product
from PIL import Image,ImageDraw,ImageFont
OUT=Path(__file__).resolve().parent
INK='#343C43'
def project(p):
 x,y,z=p
 return (12+5*sqrt(3)/2*(x-y),12+5*((x+y)/2-z))
def hull(points):
 points=sorted(set(points))
 def cross(o,a,b):return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
 lower=[];upper=[]
 for p in points:
  while len(lower)>1 and cross(lower[-2],lower[-1],p)<=0:lower.pop()
  lower.append(p)
 for p in reversed(points):
  while len(upper)>1 and cross(upper[-2],upper[-1],p)<=0:upper.pop()
  upper.append(p)
 return lower[:-1]+upper[:-1]
def geometry(d):
 # Сохраняем композицию выбранного варианта 03: синий пояс вокруг трёх граней.
 # Координаты зеркально симметричны, рёбра граней параллельны осям изометрии.
 outline=[(12,2),(20.2,6.735),(21.3,8),(21.3,16),(20.2,17.265),(12,22),(3.8,17.265),(2.7,16),(2.7,8),(3.8,6.735)]
 extra=(d-.27)*2
 top=[(12,3.7+extra),(18.3-extra,7.34),(12,10.98-extra),(5.7+extra,7.34)]
 left=[(4.5+extra,9.55+extra),(10.4-extra,12.956+extra),(10.4-extra,19.8-extra),(4.5+extra,16.394-extra)]
 right=[(24-x,y) for x,y in left]
 shapes=[(outline,'#347BBE'),(top,'#F0F3F6'),(left,'#C8D1D9'),(right,'#8997A3')]
 return shapes,outline
def svg(shapes,outline,inner,outer):
 lines=['<!-- Copyright 2026 B&A community. Apache License 2.0. -->','<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">']
 for vertices,color in shapes:
  pts=' '.join(f'{x:.6f},{y:.6f}' for x,y in vertices)
  lines.append(f'<polygon points="{pts}" fill="{color}" stroke="{INK}" stroke-width="{inner}" stroke-linejoin="round"/>')
 pts=' '.join(f'{x:.6f},{y:.6f}' for x,y in outline)
 lines.append(f'<polygon points="{pts}" fill="none" stroke="{INK}" stroke-width="{outer}" stroke-linejoin="round"/>')
 return '\n'.join(lines+['</svg>'])+'\n'
def raster(shapes,outline,size,inner,outer):
 ss=4 if size>=1000 else 12
 scale=size*ss/24
 image=Image.new('RGBA',(size*ss,size*ss),(0,0,0,0));draw=ImageDraw.Draw(image)
 def stroke(points,width):
  pts=[(x*scale,y*scale) for x,y in points];w=round(width*scale)
  draw.line(pts+[pts[0]],fill=INK,width=w,joint='curve')
  for x,y in pts:draw.ellipse((x-w/2,y-w/2,x+w/2,y+w/2),fill=INK)
 for vertices,color in shapes:
  draw.polygon([(x*scale,y*scale) for x,y in vertices],fill=color)
  stroke(vertices,inner)
 stroke(outline,outer)
 return image.resize((size,size),Image.Resampling.LANCZOS)
master,outline=geometry(.27)
(OUT/'bevelchamfer.svg').write_text(svg(master,outline,.65,.90),encoding='utf-8')
raster(master,outline,1000,.65,.90).save(OUT/'bevelchamfer-1000.png')
toolbar,small_outline=geometry(.32)
(OUT/'bevelchamfer-toolbar.svg').write_text(svg(toolbar,small_outline,.75,1.12),encoding='utf-8')
for size in [16,24,32,48]:
 raster(toolbar,small_outline,size,.85 if size==16 else .75,1.12).save(OUT/f'bevelchamfer-{size}.png')
preview=Image.new('RGB',(800,540),'#F5F5F4');d=ImageDraw.Draw(preview)
font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',18)
heading=ImageFont.truetype('C:/Windows/Fonts/seguisb.ttf',25)
d.text((24,20),'bevelchamfer · вариант 03',font=heading,fill=INK)
big=raster(master,outline,410,.65,.90);preview.paste(big,(18,85),big)
d.text((480,93),'Иконка панели',font=heading,fill=INK)
for row,bg in enumerate(['#FFFFFF','#252A2F']):
 y=150+row*135;d.rounded_rectangle((464,y,772,y+100),radius=12,fill=bg)
 for size,x in [(16,488),(24,550),(32,622),(48,704)]:
  img=Image.open(OUT/f'bevelchamfer-{size}.png');preview.paste(img,(x,y+32),img)
  d.text((x-2,y+106),str(size)+' px',font=font,fill=INK)
preview.save(OUT/'preview.png')
(OUT/'README.md').write_text('# Доработанный вариант 03\n\nГеометрически точный изометрический куб со срезанными рёбрами. Прозрачный фон.\n\n- `bevelchamfer-1000.png` — 1000×1000 px.\n- `bevelchamfer.svg` — векторный оригинал.\n- `bevelchamfer-toolbar.svg` — оптически адаптированный SVG для панели.\n- `bevelchamfer-16.png`, `bevelchamfer-24.png` — маленькие иконки SketchUp.\n- PNG 32/48 px — дополнительные размеры.\n\nМаленькая версия имеет немного более широкие фаски и усиленные линии, чтобы оставаться читаемой.\n',encoding='utf-8')
print(OUT/'preview.png')
