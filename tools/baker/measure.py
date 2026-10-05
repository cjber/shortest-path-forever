"""Input hashes and Linux process resource measurements for repeatable baker runs."""

import hashlib
import json
import platform
import resource
import time
from pathlib import Path

from forever_tools.fsio import atomic_write


def tile_hashes(paths):
    return {Path(path).name: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in sorted(paths)}


def record(path, phases, started, output, metadata):
    parent = resource.getrusage(resource.RUSAGE_SELF)
    workers = resource.getrusage(resource.RUSAGE_CHILDREN)
    report = {
        **metadata,
        "python": platform.python_version(),
        "platform": platform.platform(),
        "seconds": phases,
        "total_seconds": time.perf_counter() - started,
        "parent_cpu_seconds": parent.ru_utime + parent.ru_stime,
        "worker_cpu_seconds": workers.ru_utime + workers.ru_stime,
        "parent_max_rss_kib": parent.ru_maxrss,
        "largest_worker_rss_kib": workers.ru_maxrss,
        "rss_measurement": "Linux getrusage peaks, not concurrent aggregate process memory",
        "output_sha256": hashlib.sha256(Path(output).read_bytes()).hexdigest(),
    }
    atomic_write(path, json.dumps(report, indent=2, sort_keys=True) + "\n")
