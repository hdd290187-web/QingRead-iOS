#!/usr/bin/env python3
"""Verify downloaded macOS evidence and the actual unsigned 予盈 device IPA."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import plistlib
import struct
import sys
import argparse
import subprocess

repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('run')
parser.add_argument('--benchmark-run', help='Separate verified-fixture benchmark; packaged Release source must be unchanged')
args = parser.parse_args()
folder = repo / 'releases' / ('run' + args.run)
performance_folder = repo / 'releases' / ('run' + args.benchmark_run) if args.benchmark_run else folder
metadata = dict(line.split('=', 1) for line in (folder / 'build-info.txt').read_text().splitlines() if '=' in line)
ipa = folder / 'QingRead.ipa'
summary = json.loads((folder / 'test-summary.json').read_text())
brand = json.loads((folder / 'brand-iphone15-summary.json').read_text())
assert summary['failedTests'] == 0 and summary['skippedTests'] == 3
assert summary['passedTests'] >= 62 and summary['totalTestCount'] >= 65
assert brand['failedTests'] == 0 and brand['skippedTests'] == 0 and brand['passedTests'] >= 10
large = json.loads((folder / 'Reader-Large-summary.json').read_text())
if int(metadata['build']) >= 44:
    import re
    assert large['passedTests'] >= 8 and large['failedTests'] == 0 and large['skippedTests'] == 0
    assert brand['passedTests'] >= 16
    assert summary['passedTests'] >= 82 and summary['totalTestCount'] >= 85
    log = (folder / 'tests.log').read_text()
    for test_file in ['QingReadTests/ReaderRepairTests.swift', 'QingReadTests/ScrollWindowTests.swift', 'QingReadUITests/ReaderAcceptanceTests.swift', 'QingReadUITests/ReaderIntegrityTests.swift']:
        test = repo / test_file
        suite = test.stem
        for method in re.findall(r'func (test\w+)\(', test.read_text()):
            assert re.search(re.escape(suite + ' ' + method) + r"\]' passed", log), (suite, method)
    assert not re.search(r"(?:ReaderIntegrityTests|ScrollWindowTests) test[^\n]*\]' (?:failed|exceeded execution time allowance)", log), 'A scroll integrity or UIKit window test failed or timed out before retry; do not deliver it as fixed.'
    for fixture in ['short', 'long', 'monolith']:
        report = json.loads((folder / 'performance-iphone15' / (fixture + '-optimized.json')).read_text())
        assert report['fixtureMetadata']['engineChapterCount'] == {'short': 5, 'long': 80, 'monolith': 1}[fixture]
        main_ops = report['mainThreadOperations']
        assert not main_ops.get('fileRead') and not main_ops.get('pagination') and not main_ops.get('scrollLayout')
else:
    baseline = json.loads((performance_folder / 'Baseline-summary.json').read_text())
    assert large['passedTests'] == 2 and large['failedTests'] == 0 and large['skippedTests'] == 0
    assert baseline['passedTests'] == 3 and baseline['failedTests'] == 0 and baseline['skippedTests'] == 0
    comparison = json.loads((performance_folder / 'performance-comparison/comparison.json').read_text())
    if args.benchmark_run:
        benchmark = json.loads((performance_folder / 'Benchmark-iPhone15-summary.json').read_text())
        assert benchmark['passedTests'] == 3 and benchmark['failedTests'] == 0 and benchmark['skippedTests'] == 0
        changes = subprocess.check_output(['git', 'diff', '--name-only', metadata['commit'], 'HEAD', '--', 'QingRead'], cwd=repo, text=True).splitlines()
        assert set(changes) <= {'QingRead/Services/ReaderPerformanceSeed.swift'}, changes
        seed = (repo / 'QingRead/Services/ReaderPerformanceSeed.swift').read_text().strip()
        assert seed.startswith('#if DEBUG\n') and seed.endswith('#endif') and '#else' not in seed
        for source in [comparison['optimizedCommit'], metadata['commit']]:
            changes = subprocess.check_output(['git', 'diff', '--name-only', source, metadata['commit'], '--', 'QingRead'], cwd=repo, text=True).splitlines()
            assert set(changes) <= {'QingRead/Services/ReaderPerformanceSeed.swift'}, changes
        proof_path = folder / 'validation-proof.json'
        if proof_path.exists():
            proof = json.loads(proof_path.read_text())
            assert proof['completionSourceCommit'] == metadata['commit']
            assert proof['calibratedBenchmarkRun'] == int(args.benchmark_run)
            assert proof['calibratedBenchmarkSourceCommit'] == comparison['optimizedCommit']
            assert proof['releaseCodeMatchesRegressions'] and proof['releaseCodeMatchesCalibratedBenchmark']
            changes = subprocess.check_output(['git', 'diff', '--name-only', proof['regressionSourceCommit'], metadata['commit'], '--', 'QingRead'], cwd=repo, text=True).splitlines()
            assert set(changes) <= {'QingRead/Services/ReaderPerformanceSeed.swift'}, changes
    for row in comparison['workloads']:
        before, after = row['baseline'], row['optimized']
        assert before['fixtureMetadata'] == after['fixtureMetadata']
        assert before['simulatorTargetID'] == after['simulatorTargetID']
        assert after['fixtureMetadata']['engineChapterCount'] == {'short': 5, 'long': 80, 'monolith': 1}[row['fixture']]
assert 'BUILD SUCCEEDED' in (folder / 'device-release.log').read_text()
assert 'TEST SUCCEEDED' in (folder / 'tests.log').read_text()
assert 'TEST SUCCEEDED' in (folder / 'brand-iphone15.log').read_text()
assert 'TEST SUCCEEDED' in (folder / 'reader-large.log').read_text()
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
    for hook in [b'picker-selected', b'--uitest-import-files', b'--uitest-import-result=', b'--uitest-brand-library', b'--uitest-launch-preview', b'--uitest-epub', b'--reader-performance', b'--reader-baseline', b'--uitest-performance=', b'--uitest-integrity=', b'--reader-integrity', b'--uitest-import-after-launch']:
        assert hook not in binary, hook
    font = json.loads((repo / 'docs/font-lock.json').read_text())
    assert hashlib.sha256(archive.read('Payload/QingRead.app/NotoSerifSC.ttf')).hexdigest() == font['sha256']
    if int(metadata['build']) >= 44:
        extra_font = json.loads((repo / 'docs/reader-fonts-build44.json').read_text())
        assert hashlib.sha256(archive.read('Payload/QingRead.app/LXGWWenKaiLite-Regular.ttf')).hexdigest() == extra_font['sha256']
        assert archive.read('Payload/QingRead.app/LXGWWenKaiLite-OFL.txt') == (repo / extra_font['licensePath']).read_bytes()
source_icon = repo / 'QingRead/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
icon_lock = json.loads((repo / 'design/yuying-vector/asset-lock.json').read_text())
assert hashlib.sha256(source_icon.read_bytes()).hexdigest() == icon_lock['pngSHA256']
assert hashlib.sha256((repo / icon_lock['source']).read_bytes()).hexdigest() == icon_lock['sourceSHA256']
print(json.dumps({
    'run': args.run, 'benchmarkRun': args.benchmark_run, 'commit': metadata['commit'], 'brand': info['CFBundleDisplayName'],
    'bundleID': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'sdk': info['DTSDKName'], 'unsigned': True, 'arch': 'arm64',
    'mainTests': {k: summary[k] for k in ['passedTests', 'failedTests', 'skippedTests', 'totalTestCount']},
    'iPhone15BrandTests': {k: brand[k] for k in ['passedTests', 'failedTests', 'skippedTests', 'totalTestCount']},
    'largeReaderTests': {k: large[k] for k in ['passedTests', 'failedTests', 'skippedTests', 'totalTestCount']},
    'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(), 'bytes': ipa.stat().st_size,
}, ensure_ascii=False, indent=2))
