#!/usr/bin/env python3
"""Boot the existing test destination without changing its app or data."""
import json
import subprocess
import sys
import os


def ensure_booted(device, shutdown_others=False):
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json'], text=True))
    target = next(item for group in devices['devices'].values() for item in group if item['udid'] == device)
    if shutdown_others:
        assert os.environ.get('GITHUB_ACTIONS') == 'true', 'Runner cleanup is restricted to hosted CI'
        for group in devices['devices'].values():
            for item in group:
                if item['udid'] != device and item['state'] == 'Booted':
                    subprocess.run(['xcrun', 'simctl', 'shutdown', item['udid']], check=True)
    if target['state'] != 'Booted':
        subprocess.run(['xcrun', 'simctl', 'boot', device], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)


if __name__ == '__main__':
    ensure_booted(sys.argv[1], '--shutdown-others' in sys.argv[2:])
