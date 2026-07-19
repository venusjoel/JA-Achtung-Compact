# Canonical 1x1 target mirror

This directory is a byte-for-byte mirror of the standalone root `src/` and
`info.yaml`. CI checks the mirror before RTL tests and hardening so the game
tests, root Tiny Tapeout project, and validated physical configuration cannot
silently diverge.

Validated LibreLane 3.0.3 result: 15,279.7 µm² standard-cell area, 92.6415%
utilization, +5.22364 ns setup slack, +0.03444 ns hold slack, and zero hard
signoff violations.
