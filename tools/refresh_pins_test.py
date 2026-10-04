"""Tests for the pin refresh."""

import unittest

import refresh_pins


class RefreshPinsTest(unittest.TestCase):
    def test_latest_build_orders_numerically_and_skips_other_betas(self):
        builds = {"wow_classic_beta": [{"version": v} for v in ("1.60.1.9999", "1.60.1.70205", "5.5.3.99999")]}
        self.assertEqual(refresh_pins.latest_build(builds), "1.60.1.70205")

    def test_latest_build_rejects_a_listing_without_forever(self):
        with self.assertRaises(SystemExit):
            refresh_pins.latest_build({"wow_classic_beta": [{"version": "5.5.3.99999"}]})

    def test_pin_rewrites_only_the_named_assignment(self):
        text = 'BUILD = "1.60.1.1"\nOTHER_BUILD = "x"\nURL = f"{BUILD}"\n'
        self.assertEqual(refresh_pins.pin(text, "BUILD", "1.60.1.2"), text.replace("1.60.1.1", "1.60.1.2"))

    def test_pin_rejects_a_missing_assignment(self):
        with self.assertRaises(SystemExit):
            refresh_pins.pin('BUILD = f"{x}"\n', "INFLIGHT_REV", "abc")


if __name__ == "__main__":
    unittest.main()
