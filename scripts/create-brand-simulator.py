#!/usr/bin/env python3
"""Create an iPhone 15 on the latest installed iOS for a second layout test pass."""
import json
import re
import subprocess

def simctl(*args):
    return subprocess.check_output(['xcrun', 'simctl', *args], text=True)

types = json.loads(simctl('list', 'devicetypes', '--json'))['devicetypes']
device = next(t['identifier'] for t in types if t['name'] == 'iPhone 15')
runtimes = json.loads(simctl('list', 'runtimes', '--json'))['runtimes']
ios = [r for r in runtimes if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
runtime = max(ios, key=lambda r: tuple(int(x) for x in re.findall(r'\d+', r['version'])))['identifier']
print(simctl('create', 'Yuying iPhone 15', device, runtime).strip())
