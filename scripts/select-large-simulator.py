#!/usr/bin/env python3
"""Prefer an existing large iPhone on the latest installed runtime."""
import json
from pathlib import Path
import re
import subprocess
import sys

devices = json.loads(Path(sys.argv[1]).read_text())['devices']
choices = []
for runtime, group in devices.items():
    if '.iOS-' not in runtime:
        continue
    version = tuple(int(x) for x in re.findall(r'\d+', runtime.split('.iOS-')[-1]))
    for device in group:
        if device.get('isAvailable') and device['name'].startswith('iPhone') and 'Pro Max' in device['name']:
            choices.append((version, device['name'], device['udid']))
if choices:
    print(max(choices)[2])
else:
    print(subprocess.check_output([sys.executable, 'scripts/create-brand-simulator.py', 'iPhone 16 Pro Max'], text=True).strip())
