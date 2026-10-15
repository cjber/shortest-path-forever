#!/usr/bin/env python3
"""Check this machine against every tool pin in ci.yml and typecheck.sh, with a fix for each problem
(forever_tools.doctor).

    python3 tools/doctor.py
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import doctor
except ModuleNotFoundError:
    from forever_tools import doctor


if __name__ == "__main__":
    sys.exit(doctor.main(Path(__file__).resolve().parent.parent))
