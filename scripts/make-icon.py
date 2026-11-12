#!/usr/bin/env python3
"""Original geometric book icon; no external image assets."""
import json
from pathlib import Path
from PIL import Image, ImageDraw
folder = Path(__file__).resolve().parents[1]/'QingRead/Assets.xcassets/AppIcon.appiconset'
folder.mkdir(parents=True,exist_ok=True)
image=Image.new('RGB',(1024,1024),(31,48,44)); draw=ImageDraw.Draw(image)
draw.rounded_rectangle((214,206,810,818),radius=38,fill=(240,230,202))
draw.rounded_rectangle((234,216,790,786),radius=28,fill=(249,241,220))
draw.line((512,256,512,742),fill=(154,167,143),width=10)
for y in (328,400,472,544,616):
    draw.line((285,y,449,y),fill=(94,117,93),width=13)
    draw.line((574,y,738,y),fill=(94,117,93),width=13)
draw.polygon([(682,206),(732,206),(732,350),(707,324),(682,350)],fill=(169,86,62))
image.save(folder/'AppIcon.png')
(folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
(folder.parent/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
