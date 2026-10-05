import json
import os
import subprocess
import sys
import time
from pathlib import Path

started = time.perf_counter()
p = subprocess.Popen(sys.argv[2:])
_, status, usage = os.wait4(p.pid, 0)
p.returncode = os.waitstatus_to_exitcode(status)
Path(sys.argv[1]).write_text(
    json.dumps(
        {
            "wall_seconds": time.perf_counter() - started,
            "user_seconds": usage.ru_utime,
            "system_seconds": usage.ru_stime,
            "largest_process_rss_kib": usage.ru_maxrss,
        }
    )
    + "\n"
)
sys.exit(p.returncode)
