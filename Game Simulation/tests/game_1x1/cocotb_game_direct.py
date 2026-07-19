"""Cocotb side of the 1x1 direct-RAM game-logic test.

Drives tb_game_direct: buttons, vblank, and frame_start come straight from
the JSON trace, the framebuffer is a behavioral array, and the final memory
image is dumped as a text map for comparison with the Python model.
"""

from __future__ import annotations

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

from tests.common.maps import frame_bytes_1x1, map_1x1, write_text_map
from tests.common.traces import P1_LEFT, P1_RIGHT, P2_LEFT, P2_RIGHT, load_trace


CLK_PERIOD_NS = 20
STATE_OVER = 1
STATE_IDLE = 2
SETTLED_STATES = (STATE_IDLE, STATE_OVER)


async def wait_engine_settled(dut, timeout_cycles: int) -> int:
    elapsed = 0
    while elapsed < timeout_cycles:
        await ClockCycles(dut.clk, 8)
        elapsed += 8
        state = int(dut.u_engine.state.value)
        if state in SETTLED_STATES:
            return state
    raise AssertionError(
        f"Engine did not settle within {timeout_cycles} cycles, "
        f"state={int(dut.u_engine.state.value)}"
    )


async def wait_clear_done(dut, timeout_cycles: int) -> None:
    elapsed = 0
    while elapsed < timeout_cycles:
        await ClockCycles(dut.clk, 64)
        elapsed += 64
        if int(dut.u_engine.state.value) == STATE_IDLE:
            return
    raise AssertionError("Timed out waiting for the initial framebuffer clear")


@cocotb.test()
async def game_direct_trace(dut):
    trace = load_trace(os.environ["ACHTUNG_TRACE"])
    frames = int(os.environ.get("ACHTUNG_FRAMES", trace.frames))
    frame_w = int(os.environ["ACHTUNG_FRAME_W"])
    frame_h = int(os.environ["ACHTUNG_FRAME_H"])
    out_map = Path(os.environ["ACHTUNG_HDL_MAP"])

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    dut.p1_left.value = 0
    dut.p1_right.value = 0
    dut.p2_left.value = 0
    dut.p2_right.value = 0
    dut.restart.value = 0
    dut.vblank.value = 0
    dut.frame_start.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 8)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    await wait_clear_done(dut, timeout_cycles=200_000)

    for frame in range(frames):
        mask = trace.button_at(frame)
        dut.p1_left.value = 1 if mask & P1_LEFT else 0
        dut.p1_right.value = 1 if mask & P1_RIGHT else 0
        dut.p2_left.value = 1 if mask & P2_LEFT else 0
        dut.p2_right.value = 1 if mask & P2_RIGHT else 0

        dut.vblank.value = 1
        dut.frame_start.value = 1
        await RisingEdge(dut.clk)
        dut.frame_start.value = 0

        await wait_engine_settled(dut, timeout_cycles=512)

        dut.vblank.value = 0
        await ClockCycles(dut.clk, 2)

    if frames >= trace.frames and trace.expected.get("death_player"):
        assert int(dut.u_engine.state.value) == STATE_OVER, (
            "Expected a terminal collision, but the 1x1 RTL is not in OVER")

    total_bytes = frame_bytes_1x1(frame_w, frame_h)
    raw = bytearray(int(dut.mem[index].value) & 0xFF for index in range(total_bytes))
    write_text_map(map_1x1(raw, frame_w, frame_h), out_map,
                   f"Achtung 1x1-minimal {frame_w}x{frame_h}")
