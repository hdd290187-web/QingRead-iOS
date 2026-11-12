#!/usr/bin/env python3
"""Capture DEBUG import/FileProvider logs on the actual booted test simulators.

XCTest may use a clone and shut it down before an after-test log show runs.
Only used on the GitHub macOS runner with original, synthetic test fixtures.
"""
import json
import signal
import subprocess
import sys
import time
from pathlib import Path

folder = Path(sys.argv[1])
folder.mkdir(parents=True, exist_ok=True)
streams = {}
running = True


def stop(*_):
    global running
    running = False


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    while running:
        listing = subprocess.run(
            ['xcrun', 'simctl', 'list', 'devices', 'booted', '--json'],
            capture_output=True, text=True, check=False, timeout=15,
        )
        if listing.returncode == 0:
            for devices in json.loads(listing.stdout)['devices'].values():
                for device in devices:
                    uid = device['udid']
                    if uid in streams:
                        old_process, old_output = streams[uid]
                        if old_process.poll() is None:
                            continue
                        old_output.close()
                    # XCTest can reboot the same device after the stream starts.
                    # Reattach and append instead of losing the rest of the run.
                    output = (folder / (uid + '.log')).open('ab')
                    command = ['xcrun', 'simctl', 'spawn', uid, 'log', 'stream',
                               '--style', 'compact', '--level', 'debug', '--predicate',
                               'subsystem == "com.hdd290187.qingread" OR subsystem CONTAINS "FileProvider" OR process CONTAINS "DocumentManager"']
                    process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
                    streams[uid] = (process, output)
        time.sleep(1)
finally:
    for process, output in streams.values():
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        output.close()
