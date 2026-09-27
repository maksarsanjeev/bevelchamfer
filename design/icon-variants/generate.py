# Copyright 2026 B&A community. Licensed under Apache License 2.0.
# Векторные варианты иконки; PNG и лист сравнения из тех же примитивов.
from pathlib import Path
from math import cos,sin,pi
from html import escape
from PIL import Image,ImageDraw,ImageFont

OUT=Path(__file__).resolve().parent
BLUE='#2B6CB0'; INK='#3B3B38'; PALE='#EEF2F5'; GREY='#CBD2D8'; DARK='#8B959E'; GREEN='#22AD7D'; ORANGE='#DD8A20'
scenes=[]
def polygon(points,fill,stroke=INK,width=1.1):return ('polygon',points,fill,stroke,width)
def line(points,color=INK,width=1.2):return ('line',points,None,color,width)
def circle(x,y,r,fill,stroke=None,width=1):return ('circle',(x,y,r),fill,stroke,width)
def arc(cx,cy,r,a,b,steps=16):return [(cx+r*cos(a+(b-a)*i/steps),cy+r*sin(a+(b-a)*i/steps)) for i in range(steps+1)]
def scene(title,shapes):scenes.append((title,shapes))

scene('Срез ребра',[
 polygon([(3,7),(12,2),(21,7),(13.7,11.2),(10.3,11.2)],PALE),
 polygon([(3,7),(10.3,11.2),(10.3,20),(3,16)],GREY),
 polygon([(21,7),(13.7,11.2),(13.7,20),(21,16)],DARK),
 polygon([(10.3,11.2),(13.7,11.2),(13.7,20),(10.3,20)],BLUE,BLUE)])
scene('Скруглённое ребро',[
 polygon([(3,7),(12,2),(21,7),(21,16),(12,21),(3,16)],PALE),
 polygon([(3,7),(12,12),(12,21),(3,16)],GREY),
 polygon([(12,12),(21,7),(21,16),(12,21)],DARK),
 line([(3,7),(10,10.9),(10.5,11.3),(11,11.7),(11.5,12.1),(12,12.7),(12,21)],BLUE,2.3),
 line([(4.3,6.3),(11.1,10.1),(11.8,10.5),(12.4,11.1),(13,11.7),(13,20.3)],'#74A6D6',0.8)])
scene('Фаски по контуру',[
 polygon([(5,6),(12,2),(19,6),(21,8),(21,16),(19,18),(12,22),(5,18),(3,16),(3,8)],BLUE,INK),
 polygon([(6,7),(12,3.7),(18,7),(12,10.5)],PALE),
 polygon([(4.8,9),(10.5,12.2),(10.5,19.7),(4.8,16.5)],GREY),
 polygon([(13.5,12.2),(19.2,9),(19.2,16.5),(13.5,19.7)],DARK)])
scene('Сечение фаски',[
 polygon([(3,3),(14,3),(21,10),(21,21),(3,21)],PALE,INK,1.4),
 polygon([(14,3),(21,10),(14,10)],BLUE,BLUE),
 line([(14,3),(21,10)],BLUE,2.5)])
scene('Сечение скругления',[
 polygon([(3,3),(12,3)]+arc(12,12,9,-pi/2,0)+[(21,21),(3,21)],PALE,INK,1.4),
 polygon([(12,3),(21,3),(21,12)]+list(reversed(arc(12,12,9,-pi/2,0))),BLUE,None),
 line(arc(12,12,9,-pi/2,0),BLUE,2.0),
 circle(12,12,1,BLUE)])
scene('Выбранное ребро',[
 line([(3,7),(12,2),(21,7),(21,17),(12,22),(3,17),(3,7)],INK,1.25),
 line([(3,7),(12,12),(21,7)],INK,1.25),line([(12,12),(12,22)],INK,1.25),
 line([(3,7),(12,2)],GREEN,2.8),circle(3,7,1.6,GREEN),circle(12,2,1.6,GREEN)])
rounded = [(3,8),(3,17),(11,21),(13,21),(21,17),(21,8),(19,5),(13,2),(11,2),(5,5)]
scene('Мягкий куб',[
 polygon(rounded,BLUE,BLUE,0.8),
 polygon([(4,7.5),(12,3),(20,7.5),(12,12)],'#85B3DF',None),
 polygon([(4,8.5),(11.3,12.7),(11.3,20),(4,16.2)],'#4E8AC2',None),
 line([(12,12.4),(12,20.4)],'#DCEBFA',1.2)])
scene('Монограмма BC',[
 polygon([(3,3),(10,3),(13,6),(13,10),(10,12),(13,14),(13,18),(10,21),(3,21)],BLUE,BLUE,0.6),
 polygon([(6,6),(9,6),(10,7),(10,9),(9,10),(6,10)],'white',None),
 polygon([(6,14),(9,14),(10,15),(10,17),(9,18),(6,18)],'white',None),
 line([(21,5),(18,3),(15,6),(15,18),(18,21),(21,19)],INK,2.1)])
scene('Угол → фаска',[
 polygon([(2,4),(10,4),(10,12),(2,12)],PALE,INK,1.15),
 line([(12,9),(20,9)],BLUE,1.5),line([(17,6.5),(20,9),(17,11.5)],BLUE,1.5),
 polygon([(12,14),(17,14),(22,19),(22,22),(12,22)],PALE,INK,1.15),
 line([(17,14),(22,19)],BLUE,2.4)])
scene('Гранёный профиль',[
 polygon([(3,8),(10,3),(16,3),(21,8),(21,16),(14,21),(3,21)],PALE),
 polygon([(3,8),(9,8),(14,13),(14,21),(3,21)],GREY),
 polygon([(9,8),(16,3),(21,8),(14,13)],ORANGE,INK),
 line([(10.7,9.7),(17.7,4.7)],'#FCE2B4',0.8),
 line([(12.3,11.3),(19.3,6.3)],'#FCE2B4',0.8),
 polygon([(14,13),(21,8),(21,16),(14,21)],DARK)])

def svg(shapes):
 parts=['<!-- Copyright 2026 B&A community. Apache License 2.0. -->','<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">']
 for kind,pts,fill,stroke,w in shapes:
  attrs=f'fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"'
  if kind=='circle':
   x,y,r=pts;parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" {attrs}/>')
  else:
   tag='polygon' if kind=='polygon' else 'polyline'; coords=' '.join(f'{x:.4f},{y:.4f}' for x,y in pts)
   parts.append(f'<{tag} points="{coords}" {attrs}/>')
 parts.append('</svg>');return '\n'.join(parts)+'\n'

def raster(shapes,size):
 factor=size*4/24
 im=Image.new('RGBA',(size*4,size*4),(0,0,0,0));d=ImageDraw.Draw(im)
 for kind,pts,fill,stroke,w in shapes:
  lw=max(1,round(w*factor))
  if kind=='circle':
   x,y,r=pts; bounds=((x-r)*factor,(y-r)*factor,(x+r)*factor,(y+r)*factor)
   d.ellipse(bounds,fill=fill,outline=stroke,width=lw)
  else:
   p=[(x*factor,y*factor) for x,y in pts]
   if kind=='polygon':d.polygon(p,fill=fill)
   if stroke:
    q=p+[p[0]] if kind=='polygon' else p
    d.line(q,fill=stroke,width=lw,joint='curve')
    for x,y in q:d.ellipse((x-lw/2,y-lw/2,x+lw/2,y+lw/2),fill=stroke)
 return im.resize((size,size),Image.Resampling.LANCZOS)

fontpath='C:/Windows/Fonts/segoeui.ttf'
font=ImageFont.truetype(fontpath,20);small=ImageFont.truetype(fontpath,14);heading=ImageFont.truetype('C:/Windows/Fonts/seguisb.ttf',28)
sheet=Image.new('RGB',(1320,790),'#F5F5F4');d=ImageDraw.Draw(sheet)
d.text((28,22),'bevelchamfer / 10 вариантов иконки',font=heading,fill=INK)
d.text((28,64),'SVG + PNG · крупный вид и реальные размеры 16 / 24 px на светлом и тёмном фоне',font=small,fill='#666666')
for i,(title,shapes) in enumerate(scenes,1):
 name=f'icon-{i:02}'
 (OUT/f'{name}.svg').write_text(svg(shapes),encoding='utf-8')
 for size in [16,24,256]:raster(shapes,size).save(OUT/f'{name}-{size}.png')
 x=24+((i-1)%5)*258;y=108+((i-1)//5)*332
 d.rounded_rectangle((x,y,x+244,y+312),radius=12,fill='white',outline='#DDDDDD',width=1)
 d.text((x+14,y+12),f'{i:02}',font=heading,fill=BLUE)
 pic=raster(shapes,142);sheet.paste(pic,(x+51,y+51),pic)
 bbox=d.textbbox((0,0),title,font=font);tw=bbox[2]-bbox[0]
 d.text((x+(244-tw)/2,y+201),title,font=font,fill=INK)
 d.rounded_rectangle((x+14,y+245,x+113,y+295),radius=6,fill='#F0F1F2')
 d.rounded_rectangle((x+126,y+245,x+230,y+295),radius=6,fill='#252A2F')
 for a,color in [(x+14,'#F0F1F2'),(x+126,'#252A2F')]:
  for size,offset in [(16,15),(24,54)]:
   pic=raster(shapes,size);sheet.paste(pic,(a+offset,y+257+(24-size)//2),pic)
 d.text((x+37,y+226),'16 / 24 px',font=small,fill='#777777')
 d.text((x+152,y+226),'16 / 24 px',font=small,fill='#777777')
sheet.save(OUT/'overview.png')
(OUT/'README.md').write_text('# Варианты иконки bevelchamfer\n\nТекущая иконка плагина не заменена. Все SVG имеют прозрачный фон и viewBox 24×24; PNG подготовлены в размерах 16, 24 и 256 px.\n\n![Обзор](overview.png)\n\n'+'\n'.join(f'{i}. **{title}** — [SVG](icon-{i:02}.svg), [PNG 256](icon-{i:02}-256.png).' for i,(title,_) in enumerate(scenes,1))+'\n\nГенератор `generate.py` создаёт SVG, PNG и лист обзора из общих геометрических примитивов.\n',encoding='utf-8')
print(OUT/'overview.png')
