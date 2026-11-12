#!/usr/bin/env python3
"""Read-only reference inventory. Never copies reference source into the app."""
import json, subprocess
from pathlib import Path
root = Path('/opt/projects/references')
items=[]
for name in ('vreader','SwiftBookApp','kmreader','open-reading','swift-toolkit','KRead'):
    path=root/name
    sha=subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
    items.append({'name':name,'sha':sha,'url':subprocess.check_output(['git','-C',str(path),'remote','get-url','origin'],text=True).strip()})
print(json.dumps(items,ensure_ascii=False,indent=2))
