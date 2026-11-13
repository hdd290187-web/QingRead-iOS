#!/usr/bin/env python3
"""Export only synthetic reader performance JSON, never the book library."""
from pathlib import Path
import json
import shutil
import subprocess
import sys

device, output, variant = sys.argv[1:4]
assert variant in {'baseline', 'optimized'}
# Xcode can shut down the destination after a successful test run. The app
# container remains intact; bring the same destination back before querying it.
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json'], text=True))
target = next(item for group in devices['devices'].values() for item in group if item['udid'] == device)
if target['state'] != 'Booted':
    subprocess.run(['xcrun', 'simctl', 'boot', device], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'com.hdd290187.qingread', 'data'], text=True).strip())
source = container / 'Documents/ReaderPerformance'
destination = Path(output)
destination.mkdir(parents=True, exist_ok=True)
count = 0
for path in sorted(source.glob('*-' + variant + '.json')):
    report = json.loads(path.read_text())
    assert report['fixture'] in {'short', 'long', 'monolith'}
    assert report['baseline'] == (variant == 'baseline')
    assert report['activeScrollFrames'] > 0, 'No real scrolling was sampled'
    report['simulatorTargetID'] = device
    (destination / path.name).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    count += 1
assert count == 3, f'Expected all three workload reports, got {count}'
print(f'Exported {count} synthetic {variant} reports')
