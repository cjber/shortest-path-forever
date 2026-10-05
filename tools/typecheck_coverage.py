"""Fail if LuaLS configuration could silently omit a TOC-loaded Lua file."""

import sys
from pathlib import Path

try:
    from tools.forever_tools import toc
except ModuleNotFoundError:
    from forever_tools import toc

# Folders of shipped runtime Lua: nothing here may be missing from the TOC/XML load graph.
RUNTIME_DIRS = ("Core", "Routing", "Journey", "Transport", "UI", "Data", "Locales", "Nav")


def runtime_files(root):
    return toc.runtime_files(root, RUNTIME_DIRS)


def main():
    return toc.check_coverage(Path.cwd(), RUNTIME_DIRS)


if __name__ == "__main__":
    sys.exit(main())
