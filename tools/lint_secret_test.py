"""The secret-value lint's cases live with the shared tooling; here, that this addon's guard names satisfy it."""

import unittest

from tools.lint_secret import check


class SecretTest(unittest.TestCase):
    def test_flags_an_unguarded_guid_and_takes_the_guard(self):
        self.assertTrue(check('local guid = UnitGUID("npc")\n')[0][1].startswith("secret-unguarded:"))
        self.assertEqual(check('local guid = ns.Readable(UnitGUID("npc"))\n'), [])

    def test_a_tooltip_hook_starts_behind_ns_usable(self):
        hook = "TooltipDataProcessor.AddTooltipPostCall(1, function(tooltip)\n{}\tend\nend)\n"
        self.assertEqual(check(hook.format("\tif not ns.Usable(tooltip) then\n\t\treturn\n")), [])
        self.assertTrue(check(hook.format("\tif true then\n\t\treturn\n"))[0][1].startswith("secret-forbidden:"))


if __name__ == "__main__":
    unittest.main()
