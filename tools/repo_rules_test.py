"""file-size-no-growth over the cases that have mattered: growth, a new file, a rename, a shrink and a marker."""

import unittest

from tools.repo_rules import LIMIT, oversize_growth

BIG = b"x\n" * (LIMIT + 1)
BIGGER = BIG + b"x\n"


def check(rows, head, base):
    return oversize_growth(rows, head.get, base.get)


class FileSizeTest(unittest.TestCase):
    def test_growing_a_large_file_fails(self):
        self.assertEqual(len(check([("M", "a.lua", "a.lua")], {"a.lua": BIGGER}, {"a.lua": BIG})), 1)

    def test_a_new_large_file_fails_unless_excluded(self):
        rows = [("A", "a.lua", "a.lua"), ("A", "deps.lock", "deps.lock")]
        self.assertEqual(
            check(rows, {"a.lua": BIG, "deps.lock": BIG}, {}),
            [f"a.lua:1: file-size-no-growth: grew from 0 to {LIMIT + 1} lines, over the {LIMIT}-line limit"],
        )

    def test_a_rename_compares_with_the_old_path(self):
        self.assertEqual(len(check([("R", "old.lua", "new.lua")], {"new.lua": BIGGER}, {"old.lua": BIG})), 1)
        self.assertEqual(check([("R", "old.lua", "new.lua")], {"new.lua": BIG}, {"old.lua": BIG}), [])

    def test_shrinking_a_large_file_passes(self):
        self.assertEqual(check([("M", "a.lua", "a.lua")], {"a.lua": BIG}, {"a.lua": BIGGER}), [])

    def test_a_marker_needs_a_reason(self):
        marked = b"-- rule-ignore: file-size-no-growth - one generated lookup table\n" + BIG
        bare = b"-- rule-ignore: file-size-no-growth - ok\n" + BIG
        self.assertEqual(check([("A", "a.lua", "a.lua")], {"a.lua": marked}, {}), [])
        self.assertEqual(len(check([("A", "a.lua", "a.lua")], {"a.lua": bare}, {})), 1)


if __name__ == "__main__":
    unittest.main()
