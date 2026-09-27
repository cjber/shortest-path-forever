"""Fail if LuaLS configuration could silently omit a TOC-loaded Lua file."""

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def runtime_files(root):
    files = set()

    def visit(path):
        path = path.resolve()
        path.relative_to(root)
        if not path.is_file():
            raise ValueError(f"Missing runtime file: {path}")
        if path in files:
            return
        files.add(path)
        if path.suffix.lower() == ".xml":
            for element in ET.parse(path).iter():
                if element.tag.rsplit("}", 1)[-1] in {"Include", "Script"} and "file" in element.attrib:
                    visit(path.parent / element.attrib["file"].replace("\\", "/"))

    for toc in root.rglob("*.toc"):
        if any(part.startswith(".") or part == "node_modules" for part in toc.relative_to(root).parts):
            continue
        for line in toc.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                visit(toc.parent / line.replace("\\", "/"))
    # These directories contain shipped runtime Lua in this addon family, never checker fixtures.
    for folder in (root, root / "Data", root / "Locales", root / "UI", root / "Transport"):
        for path in folder.rglob("*.lua") if folder != root else root.glob("*.lua"):
            if path.resolve() not in files:
                raise ValueError(f"Runtime Lua is not loaded by a TOC/XML: {path.relative_to(root)}")
    return sorted(path for path in files if path.suffix.lower() == ".lua")


def main():
    root = Path.cwd().resolve()
    config = json.loads((root / ".luarc.json").read_text())
    if config.get("workspace.useGitIgnore", True):
        raise ValueError("Set workspace.useGitIgnore=false so runtime coverage does not depend on local git ignores")
    files = runtime_files(root)
    if not files:
        raise ValueError("No TOC-loaded Lua files found")
    for path in files:
        relative = path.relative_to(root)
        for ignored in config.get("workspace.ignoreDir", []):
            if relative.match(ignored) or any(parent.match(ignored) for parent in relative.parents):
                raise ValueError(f"Runtime file excluded by {ignored}: {relative}")
        if path.stat().st_size > 10 * 1024 * 1024:
            raise ValueError(f"Runtime file exceeds LuaLS's hard 10 MiB limit: {relative}")
        if path.stat().st_size / 1000 >= config["workspace.preloadFileSize"]:
            raise ValueError(f"Runtime file exceeds workspace.preloadFileSize: {relative}")
    if len(files) > config["workspace.maxPreload"]:
        raise ValueError("Runtime files exceed workspace.maxPreload")
    print(f"LuaLS coverage: {len(files)} TOC-loaded Lua files, including generated data and child addons")
    return 0


if __name__ == "__main__":
    sys.exit(main())
