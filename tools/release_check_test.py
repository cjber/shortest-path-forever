"""A tag, an older green commit or an incomplete CI run cannot authorize publishing."""

import unittest

from tools.release_check import verified


class ReleaseTest(unittest.TestCase):
    def test_exact_completed_main_ci_is_required(self):
        green = {
            "head_sha": "abc",
            "head_branch": "main",
            "path": ".github/workflows/ci.yml",
            "event": "push",
            "status": "completed",
            "conclusion": "success",
        }
        self.assertTrue(verified([green], "abc"))
        self.assertFalse(verified([], "abc"))
        for key, wrong in [
            ("head_sha", "old"),
            ("head_branch", "feature"),
            ("path", ".github/workflows/release.yml"),
            ("event", "workflow_dispatch"),
            ("status", "in_progress"),
            ("conclusion", "failure"),
            ("conclusion", "skipped"),
        ]:
            with self.subTest(key=key, wrong=wrong):
                self.assertFalse(verified([{**green, key: wrong}], "abc"))
