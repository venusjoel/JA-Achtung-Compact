# 1x1 game verification

The maintained 1x1 simulation suite is in `tests/game_1x1`. It compares the
validated target HDL against an independent Python game/framebuffer model and
also exercises the real VGA, QSPI PSRAM, gamepad, and arbitration paths.

Run from the repository root:

```sh
python "Game Simulation/tests/game_1x1/run.py" --test all --rebuild
python "Game Simulation/tests/ram/run.py" --target 1x1-minimal --rebuild
```

Generated output is written below `Game Simulation/tests/out/` and is ignored
by Git. The committed coarse and full traces are deterministic test inputs.
