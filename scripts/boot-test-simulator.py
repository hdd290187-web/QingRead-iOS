#!/usr/bin/env python3
"""Boot the existing test destination without changing its app or data."""
import json
import subprocess
import sys


def ensure_booted(device):
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json'], text=True))
    target = next(item for group in devices['devices'].values() for item in group if item['udid'] == device)
    if target['state'] != 'Booted':
        subprocess.run(['xcrun', 'simctl', 'boot', device], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)


if __name__ == '__main__':
    ensure_booted(sys.argv[1])
