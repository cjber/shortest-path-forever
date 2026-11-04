"""Travel-board chat output from the production formatter and a disposable fixture."""

import subprocess
from pathlib import Path

from wowmock import ARIALN, WHITE, Font, scene

ROOT = Path(__file__).resolve().parent.parent


def render_leaderboard(ui):
    lines = subprocess.check_output(["luajit", "tools/progress_scene.lua"], cwd=ROOT, text=True).splitlines()
    # Native chat uses ARIALN through ChatFontNormal; show the actual production formatter's lines.
    font = Font(ARIALN, 14, WHITE, (1, -1))
    measure = ui.canvas(1, 1)
    width = max(measure.text_width(line, font) for line in lines) + 24
    canvas = ui.canvas(width, 24 + len(lines) * 22)
    for index, line in enumerate(lines):
        canvas.text(12, 12 + index * 22, line, font)
    return scene(ui, [(canvas, 0, 0)])
