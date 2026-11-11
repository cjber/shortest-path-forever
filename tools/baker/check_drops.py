"""Compile and exercise the actual patched ledge-drop helper without needing client data."""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("build", type=Path)
    args = parser.parse_args()
    code = (args.source / "src/common/mmaps_common/Generator/TileBuilder.cpp").read_text()
    helper = code.split("// SPF-DROP-BEGIN", 1)[1].split("// SPF-DROP-END", 1)[0]
    with tempfile.TemporaryDirectory(prefix="spf-drops-") as directory:
        root = Path(directory)
        (root / "drops.inc").write_text(helper)
        binary = root / "ledge-test"
        subprocess.run(
            [
                os.environ.get("CXX", "c++"),
                "-std=c++20",
                "-O2",
                "-I",
                str(args.source / "dep/recastnavigation/Recast/Include"),
                "-I",
                str(root),
                str(Path(__file__).with_name("ledge_test.cpp")),
                str(args.build / "dep/recastnavigation/Recast/libRecast.a"),
                "-o",
                str(binary),
            ],
            check=True,
        )
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
