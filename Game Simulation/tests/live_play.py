"""Record the standalone 1x1 game in a native Windows window.

Usage: python tests/live_play.py [1x1-minimal]
Writes tests/out/game_1x1/live/live_trace.json.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests.common.live_record import record_live_trace

TARGET_FOLDERS = {"1x1-minimal": "game_1x1"}


def main() -> int:
    target = sys.argv[1] if len(sys.argv) > 1 else "1x1-minimal"
    folder = TARGET_FOLDERS[target]
    out = Path(__file__).resolve().parent / "out" / folder / "live" / "live_trace.json"
    record_live_trace(
        target,
        out,
        frame_w=640,
        frame_h=480,
        preview_map_path=out.with_name("live_python_preview.txt"),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
