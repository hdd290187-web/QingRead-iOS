#!/usr/bin/env python3
"""Select the latest installed iOS runtime instead of the first/oldest runtime."""
import json
import re
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
choices = []
for runtime, devices in data['devices'].items():
    if '.iOS-' not in runtime:
        continue
    version = tuple(int(number) for number in re.findall(r'\d+', runtime.split('.iOS-')[-1]))
    for device in devices:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            choices.append((version, device['name'], device['udid']))
if not choices:
    raise SystemExit('No available iPhone simulator')
print(max(choices)[2])
