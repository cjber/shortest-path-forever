"""Exact food, drink and profession trainer readings from tiny fixture rows."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_services import (
    class_trainers,
    food_and_drink,
    profession_skill_spells,
    profession_trainers,
    skill_line_categories,
)


def creature(entry, trainer_type, trainer_class=0, template=0, name=None):
    return {
        "Entry": str(entry),
        "Name": name or f"Trainer {entry}",
        "TrainerType": str(trainer_type),
        "TrainerClass": str(trainer_class),
        "TrainerTemplateId": str(template),
    }


def effect(spell, aura=0, effect=0, trigger=0, misc=0):
    return {
        "SpellID": str(spell),
        "EffectAura": str(aura),
        "Effect": str(effect),
        "EffectTriggerSpell": str(trigger),
        "EffectMiscValue_0": str(misc),
    }


class FoodDrinkTest(unittest.TestCase):
    def test_a_use_spell_or_one_trigger_hop_decides_food_and_drink(self):
        items = [
            {"ItemID": "1", "ItemEffectID": "10"},
            {"ItemID": "2", "ItemEffectID": "11"},
            {"ItemID": "3", "ItemEffectID": "12"},
            {"ItemID": "4", "ItemEffectID": "13"},
        ]
        use = [
            {"ID": "10", "SpellID": "100"},
            {"ID": "11", "SpellID": "101"},
            {"ID": "12", "SpellID": "102"},
            {"ID": "13", "SpellID": "103"},
        ]
        spells = [
            effect(100, aura=84),
            effect(101, aura=85),
            effect(102, effect=64, trigger=200),
            effect(200, aura=85),
            effect(103, aura=99),
        ]
        food, drink = food_and_drink(items, use, spells)
        self.assertEqual(food, [1])
        self.assertEqual(drink, [2, 3])


class SkillTest(unittest.TestCase):
    def test_only_profession_and_secondary_skill_lines_are_learned(self):
        categories = skill_line_categories(
            [
                {"ID": "171", "CategoryID": "11"},
                {"ID": "356", "CategoryID": "9"},
                {"ID": "6", "CategoryID": "7"},
            ]
        )
        learned = profession_skill_spells(
            [
                {"Spell": "1100", "SkillLine": "171"},
                {"Spell": "1101", "SkillLine": "6"},
                {"Spell": "1102", "SkillLine": "356"},
            ],
            categories,
        )
        self.assertEqual(learned, {1100: {171}, 1102: {356}})


class TrainerTest(unittest.TestCase):
    def test_learn_spells_name_one_skill_line_each(self):
        creatures = [
            creature(1, 2),
            creature(2, 2, template=5),
            creature(3, 2),
        ]
        trainers = [{"entry": "1", "spell": "1000"}, {"entry": "3", "spell": "1002"}]
        templates = [{"entry": "5", "spell": "2000"}]
        spells = [
            effect(1000, effect=36, trigger=1100),
            effect(1002, effect=36, trigger=1102),
            effect(2000, effect=36, trigger=1200),
        ]
        skills = {1100: {171}, 1200: {165}}
        self.assertEqual(profession_trainers(creatures, trainers, templates, spells, skills), {1: 171, 2: 165})

    def test_two_skill_lines_name_the_trainer(self):
        creatures = [creature(4, 2, name="Mixed Trainer")]
        trainers = [{"entry": "4", "spell": "1000"}, {"entry": "4", "spell": "1001"}]
        spells = [
            effect(1000, effect=36, trigger=1100),
            effect(1001, effect=36, trigger=1101),
        ]
        with self.assertRaisesRegex(ValueError, "Mixed Trainer"):
            profession_trainers(creatures, trainers, [], spells, {1100: {171}, 1101: {165}})

    def test_class_trainers_keep_only_a_real_class(self):
        self.assertEqual(
            class_trainers([creature(7, 0, trainer_class=3), creature(8, 0), creature(9, 2, trainer_class=3)]),
            {7: 3},
        )


if __name__ == "__main__":
    unittest.main()
