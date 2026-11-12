#!/usr/bin/env python3
"""Download exact-version license texts only, preserving upstream notices verbatim."""
import concurrent.futures, json, urllib.request
from pathlib import Path
root = Path(__file__).resolve().parents[1]
pins = json.loads((root/'Package.resolved').read_text())['pins']
folder = root/'QingRead/Resources/Notices'
def fetch(pin):
    repo=pin['location'].removesuffix('.git').replace('https://github.com/','')
    revision=pin['state']['revision']
    for candidate in ('LICENSE','LICENSE.md','LICENSE.txt','COPYING','License.md','LICENSE-MIT'):
        url=f'https://raw.githubusercontent.com/{repo}/{revision}/{candidate}'
        try:
            with urllib.request.urlopen(url,timeout=30) as response: data=response.read()
            if len(data)<100: continue
            target=folder/(pin['identity']+'-LICENSE.txt')
            target.write_bytes(data)
            return f'{pin["identity"]}: {target.name} ({len(data)} bytes)'
        except Exception: continue
    raise RuntimeError(f'Missing license: {repo} at {revision}')
folder.mkdir(parents=True,exist_ok=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
    for result in executor.map(fetch,pins): print(result)
