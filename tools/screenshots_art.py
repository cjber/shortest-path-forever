"""Reviewed UI artwork with map and quest data from the generated client build."""

import csv
from pathlib import Path

from gen_routes import BUILD as DATA_BUILD
from wowmock import Ui  # ty: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
UI_ART_BUILD = "1.60.1.70124"


class Content(Ui):
    """Read the generated build, reusing the generator's local CSV cache."""

    def table(self, name, key="ID"):
        local = ROOT / "tools/.cache" / f"{name}-{DATA_BUILD}.csv"
        if name not in self._tables and local.is_file():
            with local.open(encoding="utf-8") as source:
                self._tables[name] = {row[key]: row for row in csv.DictReader(source)}
        return super().table(name, key)


class Art(Ui):
    """Keep native chrome independent of current map and quest content."""

    def __init__(self, *args, **kwargs):
        kwargs.setdefault("build", UI_ART_BUILD)
        super().__init__(*args, **kwargs)
        self.data = Content(build=DATA_BUILD, scale=self.scale)
        self._atlas_cache = {}

    def atlas(self, name):
        if name not in self._atlas_cache:
            self._atlas_cache[name] = super().atlas(name)
        return self._atlas_cache[name]
