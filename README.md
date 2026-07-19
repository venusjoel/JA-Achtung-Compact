# JA Achtung Compact — 1x1

This repository is the standalone one-tile version of our two-player
*Achtung, die Kurve!* hardware game for Tiny Tapeout. It uses cardinal
movement, a 1-bit external QSPI PSRAM framebuffer, and direct 640×480 VGA.

The Tiny Tapeout project is entirely at the repository root:

- `src/`: exact 1x1 HDL and LibreLane configuration
- `info.yaml`: 1x1 project metadata and pinout
- `docs/info.md`: datasheet source
- `test/`: root RTL and gate-level pin smoke tests
- `Game Simulation/tests/game_1x1/`: 1x1 VGA, game-model, and system tests
- `targets/1x1-minimal/`: byte-for-byte canonical mirror used by CI

## Validation baseline

The exact HDL and configuration in this project were validated with LibreLane
3.0.3 and sky130A PDK revision `8afc8346`:

- standard-cell area: 15,279.7 µm²
- final utilization: 92.6415%
- worst setup slack: +5.22364 ns
- worst hold slack: +0.03444 ns
- setup, hold, routing DRC, Magic DRC, LVS, and antenna violations: 0
- Tiny Tapeout precheck: 15/15 passed
- powered gate-level QSPI/VGA smoke test: passed

The full 1x1 verification also covers a real 640×480 VGA frame, all 21 game
traces, collision semantics, gamepad input, QSPI traffic, and arbitration.

## Local tests

```sh
python "Game Simulation/tests/game_1x1/run.py" --test all --rebuild
python "Game Simulation/tests/ram/run.py" --target 1x1-minimal --rebuild
cd test && make -B
```

The framebuffer is external. Hardware use requires a compatible QSPI PSRAM,
the Tiny Tapeout VGA PMOD, and the Gamepad PMOD. See `docs/info.md` for the
power-up sequence and pinout.
