#!/usr/bin/env python3
"""Reproducible development render, independent of the iOS runtime.

Requires CairoSVG 2.8.2 and Pillow. Render the editable SVG at 4x resolution,
then downsample. AppIcon is an opaque RGB square; the logo retains alpha.
"""
from pathlib import Path
from io import BytesIO
import hashlib
import json
import xml.etree.ElementTree as ET
import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
VECTOR = ROOT / 'design/yuying-vector'
ASSETS = ROOT / 'QingRead/Assets.xcassets'
source = VECTOR / 'AppIcon.svg'
svg = ET.parse(source).getroot()
ns = {'svg': 'http://www.w3.org/2000/svg'}
assert svg.attrib['viewBox'] == '0 0 1024 1024'
assert not svg.findall('.//svg:image', ns)
assert not svg.findall('.//svg:text', ns)
background = svg.find("svg:g[@id='square-background']", ns)
assert background is not None
rect = background.find('svg:rect', ns)
assert rect is not None and 'rx' not in rect.attrib and 'ry' not in rect.attrib
data = cairosvg.svg2png(url=str(source), output_width=4096, output_height=4096)
icon = Image.open(BytesIO(data)).convert('RGB').resize((1024, 1024), Image.Resampling.LANCZOS)
target = ASSETS / 'AppIcon.appiconset/AppIcon.png'
icon.save(target, optimize=True)

# The same editable book paths become the transparent in-app mark.
svg.remove(background)
svg.set('viewBox', '110 274 804 546')
svg.set('width', '804'); svg.set('height', '546')
ET.register_namespace('', ns['svg'])
symbol = VECTOR / 'BrandSymbol.svg'
ET.ElementTree(svg).write(symbol, encoding='utf-8', xml_declaration=True)
mark_data = cairosvg.svg2png(url=str(symbol), output_width=3216, output_height=2184)
mark = Image.open(BytesIO(mark_data)).convert('RGBA').resize((804, 546), Image.Resampling.LANCZOS)
mark.save(ASSETS / 'BrandMark.imageset/BrandMark.png', optimize=True)

for size in [60, 180]:
    icon.resize((size, size), Image.Resampling.LANCZOS).save(VECTOR / f'icon-preview-{size}.png')
manifest = {
    'origin': 'Original editable vector reconstruction following the latest user instruction',
    'request': 'design/yuying-reference/latest-instructions.txt',
    'source': 'design/yuying-vector/AppIcon.svg',
    'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'png': 'QingRead/Assets.xcassets/AppIcon.appiconset/AppIcon.png',
    'pngSHA256': hashlib.sha256(target.read_bytes()).hexdigest(),
    'pixels': [1024, 1024], 'mode': 'RGB', 'alpha': False, 'bakedSystemCorners': False,
    'renderer': 'CairoSVG 2.8.2, 4x supersampling, Pillow Lanczos',
    'license': 'Original paths/code under the repository MIT license; user supplied design reference',
}
(VECTOR / 'asset-lock.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(manifest, ensure_ascii=False, indent=2))
