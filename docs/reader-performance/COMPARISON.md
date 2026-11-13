# Continuous scrolling: measured Simulator comparison

Both versions run the same original fixtures and identical touch gestures on the same iPhone 15 simulator. Values are observed, not an assertion of real-device smoothness.

| Fixture / verified chapters / UTF-16 | Frame p95 ms before / after | Max frame ms before / after | Frames over 1.5 budgets before / after | Peak resident MiB before / after |
| --- | --- | --- | --- | --- |
| short / 5 / 4390 | 16.67 / 16.67 | 70.47 / 63.53 | 55 / 8 | 361.1 / 457.0 |
| long / 80 / 591411 | 16.67 / 16.67 | 79.01 / 81.97 | 66 / 7 | 370.9 / 446.7 |
| monolith / 1 / 373904 | 16.67 / 16.67 | 83.78 / 53.81 | 83 / 3 | 709.6 / 493.2 |

Per-operation counts, p95 and maximum main-thread times are in comparison.json. Frame time on a shared virtual runner is noisy; regressions or inconclusive results must be reported as observed.

HUMAN_PENDING: repeat with Time Profiler / Hangs / Core Animation on the user’s iPhone before claiming the reported device stutter is resolved.
