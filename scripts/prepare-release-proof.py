#!/usr/bin/env python3
"""Verify completed regression evidence before a release completion build."""
from pathlib import Path
import json
import shutil
import subprocess
import sys

regression, benchmark, output = map(Path, sys.argv[1:4])
run = json.loads((output / 'regression-run.json').read_text())
source = run['headSha']
assert run['status'] == 'completed'
steps = {s['name']: s['conclusion'] for job in run['jobs'] for s in job['steps']}
for name in ['Device Release build', 'Run tests on iPhone Simulator', 'Brand layouts on iPhone 15']:
    assert steps[name] == 'success', (name, steps.get(name))
main = json.loads((regression / 'test-summary.json').read_text())
brand = json.loads((regression / 'brand-iphone15-summary.json').read_text())
assert main['passedTests'] >= 62 and main['failedTests'] == 0 and main['skippedTests'] == 3
assert brand['passedTests'] >= 10 and brand['failedTests'] == 0 and brand['skippedTests'] == 0
comparison = json.loads((benchmark / 'performance-comparison/comparison.json').read_text())
benchmark_run = json.loads((output / 'benchmark-run.json').read_text())
assert benchmark_run['status'] == 'completed' and benchmark_run['conclusion'] == 'success'
assert comparison['optimizedCommit'] == benchmark_run['headSha']
for name in ['Benchmark-iPhone15-summary.json', 'Baseline-summary.json']:
    summary = json.loads((benchmark / name).read_text())
    assert summary['passedTests'] == 3 and summary['failedTests'] == 0 and summary['skippedTests'] == 0
assert sorted(row['fixture'] for row in comparison['workloads']) == ['long', 'monolith', 'short']
for row in comparison['workloads']:
    before, after = row['baseline'], row['optimized']
    assert before['fixtureMetadata'] == after['fixtureMetadata']
    assert before['simulatorTargetID'] == after['simulatorTargetID']
    assert after['fixtureMetadata']['engineChapterCount'] == {'short': 5, 'long': 80, 'monolith': 1}[row['fixture']]
for original in [source, comparison['optimizedCommit']]:
    subprocess.run(['git', 'merge-base', '--is-ancestor', original, 'HEAD'], check=True)
    changes = subprocess.check_output(['git', 'diff', '--name-only', original, 'HEAD', '--', 'QingRead'], text=True).splitlines()
    assert set(changes) <= {'QingRead/Services/ReaderPerformanceSeed.swift'}, changes
    for revision in [original, 'HEAD']:
        seed = subprocess.check_output(['git', 'show', revision + ':QingRead/Services/ReaderPerformanceSeed.swift'], text=True).strip()
        assert seed.startswith('#if DEBUG\n') and seed.endswith('#endif') and '#else' not in seed
output.mkdir(parents=True, exist_ok=True)
for name in ['test-summary.json', 'brand-iphone15-summary.json', 'tests.log', 'brand-iphone15.log']:
    shutil.copy2(regression / name, output / name)
for group in ['screenshots', 'brand-iphone15-screenshots']:
    src = regression / group
    dst = output / group
    dst.mkdir(exist_ok=True)
    selected = []
    for test in json.loads((src / 'manifest.json').read_text()):
        if not any(x in test['testIdentifier'] for x in ['ReaderLayoutTests/', 'BrandUITests/']):
            continue
        attachments = [a for a in test['attachments'] if a['exportedFileName'].endswith('.png')]
        for attachment in attachments:
            name = attachment['exportedFileName']
            shutil.copy2(src / name, dst / name)
        selected.append({**test, 'attachments': attachments})
    (dst / 'manifest.json').write_text(json.dumps(selected, ensure_ascii=False, indent=2) + '\n')
proof = {'regressionRun': run['databaseId'], 'regressionSourceCommit': source,
         'regressionOverallConclusion': run['conclusion'], 'releaseCodeMatchesRegressions': True,
         'main': {k: main[k] for k in ['passedTests', 'failedTests', 'skippedTests', 'totalTestCount']},
         'iPhone15': {k: brand[k] for k in ['passedTests', 'failedTests', 'skippedTests', 'totalTestCount']},
         'calibratedBenchmarkSourceCommit': comparison['optimizedCommit'],
         'calibratedBenchmarkRun': benchmark_run['databaseId'],
         'releaseCodeMatchesCalibratedBenchmark': True,
         'completionSourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
         'remainingValidation': 'Fresh large-iPhone layouts and the actual arm64 Release package'}
(output / 'validation-proof.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n')
print('Verified original complete main/iPhone15 regressions, calibrated benchmark, and unchanged Release code.')
