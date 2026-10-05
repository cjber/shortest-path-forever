"""Report keyed changes in generated journey data."""

from pathlib import Path

try:
    from tools.check_generated import DATA
    from tools.forever_tools.generated import data_report
except ModuleNotFoundError:
    from check_generated import DATA
    from forever_tools.generated import data_report

if __name__ == "__main__":
    data_report(Path(__file__).resolve().parent.parent, DATA)
