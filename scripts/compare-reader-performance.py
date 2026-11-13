#!/usr/bin/env python3
"""Report measured results without assuming that Simulator predicts device feel."""
from pathlib import Path
import json
import os
import sys

baseline_dir, optimized_dir, output = map(Path, sys.argv[1:4])
results = []
for fixture in ['short', 'long', 'monolith']:
    before = json.loads((baseline_dir / f'{fixture}-baseline.json').read_text())
    after = json.loads((optimized_dir / f'{fixture}-optimized.json').read_text())
    assert before['environment'] == after['environment']
    assert before['simulatorTargetID'] == after['simulatorTargetID']
    assert before['simulator'] is True and after['simulator'] is True
    assert before['fixtureMetadata'] == after['fixtureMetadata'], 'The exact same verified content and chapter structure are required'
    # Architectural regressions fail independently of noisy virtual frame timing.
    main = after['mainThreadOperations']
    assert not main.get('fileRead') and not main.get('pagination') and not main.get('scrollLayout')
    assert 'pagination' not in after['operations'], 'Scroll must not paginate whole chapters'
    results.append({'fixture': fixture, 'baseline': before, 'optimized': after})
report = {
    'baselineCommit': 'd75d7b6b68f3dbf6a7e9b0dd8d012880732e0bf9',
    'optimizedCommit': os.environ.get('GITHUB_SHA', 'local'),
    'sameDevice': True, 'platform': 'iOS Simulator', 'workloads': results,
    'humanPending': 'Real iPhone frame pacing, thermal behavior, inertia and touch feel require device profiling.',
}
output.mkdir(parents=True, exist_ok=True)
(output / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
lines = ['# Continuous scrolling: measured Simulator comparison', '',
         'Both versions run the same original fixtures and identical touch gestures on the same iPhone 15 simulator. Values are observed, not an assertion of real-device smoothness.', '',
         '| Fixture / verified chapters / UTF-16 | Frame p95 ms before / after | Max frame ms before / after | Frames over 1.5 budgets before / after | Peak resident MiB before / after |',
         '| --- | --- | --- | --- | --- |']
for row in results:
    a, b = row['baseline'], row['optimized']
    fixture = a['fixtureMetadata']
    lines.append(f"| {row['fixture']} / {fixture['engineChapterCount']} / {fixture['totalUTF16']} | {a['frameP95Ms']:.2f} / {b['frameP95Ms']:.2f} | {a['frameMaxMs']:.2f} / {b['frameMaxMs']:.2f} | {a['framesOver1_5Budgets']} / {b['framesOver1_5Budgets']} | {a['peakResidentBytes']/1048576:.1f} / {b['peakResidentBytes']/1048576:.1f} |")
lines += ['', 'Per-operation counts, p95 and maximum main-thread times are in comparison.json. Frame time on a shared virtual runner is noisy; regressions or inconclusive results must be reported as observed.', '', 'HUMAN_PENDING: repeat with Time Profiler / Hangs / Core Animation on the user’s iPhone before claiming the reported device stutter is resolved.']
(output / 'COMPARISON.md').write_text('\n'.join(lines) + '\n')
print('Wrote measured comparison; no device smoothness claim')
