#!/usr/bin/env python3
"""Verify downloaded macOS evidence and the actual unsigned 予盈 device IPA."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import plistlib
import struct
import sys

repo = Path(__file__).resolve().parents[1]
folder = repo / 'releases' / ('run' + sys.argv[1])
metadata = dict(line.split('=', 1) for line in (folder / 'build-info.txt').read_text().splitlines() if '=' in line)
ipa = folder / 'QingRead.ipa'
summary = json.loads((folder / 'test-summary.json').read_text())
brand = json.loads((folder / 'brand-iphone15-summary.json').read_text())
assert summary['failedTests'] == 0 and summary['skippedTests'] == 3
assert summary['passedTests'] == 52 and summary['totalTestCount'] == 55
assert brand['failedTests'] == 0 and brand['skippedTests'] == 0 and brand['passedTests'] == 5
assert 'BUILD SUCCEEDED' in (folder / 'device-release.log').read_text()
assert 'TEST SUCCEEDED' in (folder / 'tests.log').read_text()
assert 'TEST SUCCEEDED' in (folder / 'brand-iphone15.log').read_text()
with ZipFile(ipa) as archive:
    assert archive.testzip() is None
    names = archive.namelist()
    assert not any('_CodeSignature/' in n or n.endswith('embedded.mobileprovision') for n in names)
    info = plistlib.loads(archive.read('Payload/QingRead.app/Info.plist'))
    assert int(info['CFBundleVersion']) > 24
    assert info['CFBundleVersion'] == metadata['build']
    assert info['CFBundleIdentifier'] == 'com.hdd290187.qingread'
    assert info['CFBundleDisplayName'] == '予盈'
    assert info['UILaunchStoryboardName'] == 'LaunchScreen'
    assert any(n.startswith('Payload/QingRead.app/LaunchScreen.storyboardc/') for n in names)
    assert info['DTSDKName'].startswith('iphoneos')
    binary = archive.read('Payload/QingRead.app/QingRead')
    assert struct.unpack_from('<II', binary, 0) == (0xfeedfacf, 0x0100000c)
    offset = 32
    for _ in range(struct.unpack_from('<I', binary, 16)[0]):
        command, size = struct.unpack_from('<II', binary, offset)
        assert command != 0x1d  # LC_CODE_SIGNATURE
        offset += size
    for hook in [b'picker-selected', b'--uitest-import-files', b'--uitest-import-result=', b'--uitest-brand-library', b'--uitest-launch-preview', b'--uitest-epub']:
        assert hook not in binary, hook
    font = json.loads((repo / 'docs/font-lock.json').read_text())
    assert hashlib.sha256(archive.read('Payload/QingRead.app/NotoSerifSC.ttf')).hexdigest() == font['sha256']
source_icon = repo / 'QingRead/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
icon_lock = json.loads((repo / 'design/yuying-vector/asset-lock.json').read_text())
assert hashlib.sha256(source_icon.read_bytes()).hexdigest() == icon_lock['pngSHA256']
assert hashlib.sha256((repo / icon_lock['source']).read_bytes()).hexdigest() == icon_lock['sourceSHA256']
print(json.dumps({
    'run': sys.argv[1], 'commit': metadata['commit'], 'brand': info['CFBundleDisplayName'],
    'bundleID': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'sdk': info['DTSDKName'], 'unsigned': True, 'arch': 'arm64',
    'mainTests': {k: summary[k] for k in ['passedTests', 'failedTests', 'skippedTests', 'totalTestCount']},
    'iPhone15BrandTests': {k: brand[k] for k in ['passedTests', 'failedTests', 'skippedTests', 'totalTestCount']},
    'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(), 'bytes': ipa.stat().st_size,
}, ensure_ascii=False, indent=2))
