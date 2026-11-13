"""The band ladder keeps only effects whose implicit target is another unit, split by which units can answer, and
the items whose on-use spell does."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_targets import band_items, band_spells


def effect(spell, target, second=0, effect=6):
    return {
        "SpellID": str(spell),
        "Effect": str(effect),
        "ImplicitTarget_0": str(target),
        "ImplicitTarget_1": str(second),
    }


def item(item_id, effect_id):
    return {"ItemID": str(item_id), "ItemEffectID": str(effect_id)}


def use(effect_id, spell, trigger=0):
    return {"ID": str(effect_id), "TriggerType": str(trigger), "SpellID": str(spell)}


def spell_range(index, low, high):
    return {"ID": str(index), "RangeMin_0": str(low), "RangeMax_0": str(high)}


def misc(spell, index, difficulty=0):
    return {"SpellID": str(spell), "RangeIndex": str(index), "DifficultyID": str(difficulty)}


class BandSpellTest(unittest.TestCase):
    def test_keeps_a_targeted_ally_and_any_targeted_unit_as_friendly(self):
        # TARGET_UNIT_TARGET_ALLY (21), TARGET_UNIT_TARGET_CHAINHEAL_ALLY (45) and TARGET_UNIT_TARGET_ANY (25).
        rows = [effect(1459, 21), effect(1064, 45), effect(1130, 25)]
        self.assertEqual(band_spells(rows), ([1064, 1130, 1459], [1130]))

    def test_keeps_an_enemy_and_any_targeted_unit_as_hostile(self):
        # TARGET_UNIT_TARGET_ENEMY (6) and TARGET_UNIT_TARGET_ANY (25).
        rows = [effect(133, 6), effect(1130, 25)]
        self.assertEqual(band_spells(rows), ([1130], [133, 1130]))

    def test_drops_caster_pet_and_area_targets(self):
        # TARGET_UNIT_CASTER (1), TARGET_UNIT_PET (5) and TARGET_UNIT_AREA_ALLY (9).
        rows = [effect(11426, 1), effect(2641, 5), effect(32546, 9)]
        self.assertEqual(band_spells(rows), ([], []))

    def test_an_effect_that_targets_nothing_is_no_range_check(self):
        # Effect 0 is no effect, even where a stale target field names an ally.
        rows = [effect(1459, 21, effect=0)]
        self.assertEqual(band_spells(rows), ([], []))

    def test_any_target_on_the_second_effect_is_enough(self):
        rows = [effect(1130, 1, 25)]
        self.assertEqual(band_spells(rows), ([1130], [1130]))


class BandItemTest(unittest.TestCase):
    def test_keeps_items_whose_use_spell_targets_another_unit(self):
        rows = [item(1251, 1), item(14530, 2)]
        effects = [use(1, 746), use(2, 18610)]
        # Linen Bandage's heal targets an ally; Runecloth's too.
        self.assertEqual(
            band_items(rows, effects, [misc(746, 1), misc(18610, 1)], [spell_range(1, 0, 15)], [746, 18610], []),
            {
                1251: {"range": 15, "friendly": True},
                14530: {"range": 15, "friendly": True},
            },
        )

    def test_drops_an_item_whose_use_spell_targets_nothing(self):
        # A potion's self buff is a caster target, so its range is no check to another unit.
        self.assertEqual(
            band_items([item(1251, 1)], [use(1, 11426)], [misc(11426, 1)], [spell_range(1, 0, 30)], [1459], []),
            {},
        )

    def test_drops_an_item_whose_effect_is_not_on_use(self):
        self.assertEqual(
            band_items([item(1251, 1)], [use(1, 746, trigger=1)], [misc(746, 1)], [spell_range(1, 0, 15)], [746], []),
            {},
        )

    def test_an_enemy_use_spell_makes_a_hostile_item(self):
        self.assertEqual(
            band_items([item(13256, 1)], [use(1, 17368)], [misc(17368, 1)], [spell_range(1, 0, 25)], [], [17368]),
            {13256: {"range": 25, "hostile": True}},
        )

    def test_a_minimum_range_still_stores_the_maximum(self):
        # The 8-30 yd row bounds from above by 30, which is what the band uses.
        self.assertEqual(
            band_items([item(11905, 1)], [use(1, 15712)], [misc(15712, 1)], [spell_range(1, 8, 30)], [], [15712]),
            {11905: {"range": 30, "hostile": True}},
        )

    def test_reads_the_normal_difficulty_row(self):
        rows = [item(1251, 1)]
        effects = [use(1, 746)]
        spells = [misc(746, 2, difficulty=186), misc(746, 1)]
        ranges = [spell_range(1, 0, 15), spell_range(2, 0, 40)]
        self.assertEqual(
            band_items(rows, effects, spells, ranges, [746], []),
            {1251: {"range": 15, "friendly": True}},
        )

    def test_keeps_both_sides_when_the_use_spell_targets_any_unit(self):
        self.assertEqual(
            band_items([item(13256, 1)], [use(1, 17368)], [misc(17368, 1)], [spell_range(1, 0, 25)], [17368], [17368]),
            {13256: {"range": 25, "friendly": True, "hostile": True}},
        )


if __name__ == "__main__":
    unittest.main()
