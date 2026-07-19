# Standalone 1x1 tests

- `game_1x1/`: full and coarse game traces, direct-FSM comparison, VGA, and
  complete-system tests for the 1x1 HDL
- `common/`: shared Python model, QSPI/gamepad BFMs, trace generation, and
  top-level Cocotb tests
- `ram/`: standalone PSRAM controller and display-streamer tests using the
  exact `targets/1x1-minimal/src` files

The workflow regenerates the committed traces and fails if they differ, then
runs real 640×480 VGA, full and coarse suites, system smoke, and RAM tests.
