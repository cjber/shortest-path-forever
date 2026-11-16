#!/usr/bin/env python3
"""Generate food, drink, trainer and battlemaster tables for the pinned Forever client (stdlib)."""

import argparse
import csv
import gzip
import re
import sys
import urllib.error
from collections import defaultdict

from gen_routes import BUILD, CACHE, ROOT, db2
from gen_transit import DB_REV, DB_URL, lua, render

try:
    from tools.forever_tools.fsio import publish
    from tools.forever_tools.wago import fetch
except ModuleNotFoundError:
    from forever_tools.fsio import publish
    from forever_tools.wago import fetch

# SpellEffect.EffectAura: MOD_REGEN (food) and MOD_POWER_REGEN (drink).
FOOD_AURA, DRINK_AURA = 84, 85
# ItemEffect.TriggerType: on use. On equip (1) is a worn item's lasting bonus: a trinket that restores mana every 5
# seconds has the drink's MOD_POWER_REGEN aura without being drunk.
ON_USE = 0
# SpellEffect.Effect: a use spell can hand its work to another spell one hop away.
TRIGGER_SPELL = 64
# SpellEffect.Effect: a trainer spell teaches the spell it triggers.
LEARN_SPELL = 36
# SpellEffect.Effect: the spell opens a portal's transit door.
TRANS_DOOR = 50
# SkillLine.CategoryID: professions (11) and secondary skills (9).
PROFESSION_CATEGORIES = {11, 9}
# The twelve skill lines the client's Professions book shows, which GetProfessions returns: the nine primaries
# (CategoryID 11) then First Aid, Cooking and Fishing (9). SkillLine also carries riding, racial and test lines in
# those categories, and an item's RequiredSkill can name one of them, so the vendor table keeps only these.
LEARNABLE_PROFESSIONS = (129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393)
# Mage, whose portal trainers teach only the teleport spells that land at a fixed place.
MAGE = 8
CLASSIC_TABLES = (
    "creature_template",
    "npc_trainer",
    "npc_trainer_template",
    "battlemaster_entry",
    "npc_vendor",
    "spell_template",
    "spell_target_position",
)
TUPLES = re.compile(r"\(((?:'(?:\\.|[^'\\])*'|[^()'])*)\)")


def classicdb(refresh=False, offline=False):
    """The classic-db tables this generator reads, in their CREATE TABLE order rather than a guessed position."""
    path = CACHE / f"classicdb-{DB_REV[:8]}.sql.gz"
    fetch(
        DB_URL,
        path,
        user_agent="ShortestPathForever/1.0",
        refresh=refresh,
        offline=offline,
        timeout=60,
        validate=gzip.decompress,
    )
    headers = {name: [] for name in CLASSIC_TABLES}
    rows = {name: [] for name in CLASSIC_TABLES}
    table = None
    with gzip.open(path, "rt", encoding="utf-8") as stream:
        for line in stream:
            opened = re.match(r"CREATE TABLE `([^`]+)`", line)
            if opened:
                name = opened.group(1)
                table = name if name in headers else None
                continue
            if table:
                column = re.match(r"\s+`([^`]+)`", line)
                if column:
                    headers[table].append(column.group(1))
                elif line.startswith(")"):
                    table = None
                continue
            insert = re.match(r"INSERT INTO `([^`]+)` VALUES ", line)
            if insert and insert.group(1) in rows:
                name = insert.group(1)
                for match in TUPLES.finditer(line):
                    values = next(csv.reader([match[1]], quotechar="'", escapechar="\\"))
                    if len(values) != len(headers[name]):
                        raise ValueError(f"classic-db {name}: {len(values)} values for {len(headers[name])} columns")
                    rows[name].append(dict(zip(headers[name], values, strict=True)))
    for name in CLASSIC_TABLES:
        if not headers[name] or not rows[name]:
            raise ValueError(f"classic-db: missing {name}")
    return rows


def food_and_drink(item_x_item_effect, item_effect, spell_effect):
    """Item IDs whose use spell has a food or drink regen aura, following one TRIGGER_SPELL hop."""
    use_spells = {int(row["ID"]): int(row["SpellID"]) for row in item_effect if int(row["TriggerType"]) == ON_USE}
    by_spell = defaultdict(list)
    for row in spell_effect:
        by_spell[int(row["SpellID"])].append(row)

    def auras(spell):
        found = set()
        for row in by_spell.get(spell, ()):
            aura = int(row["EffectAura"])
            if aura in (FOOD_AURA, DRINK_AURA):
                found.add(aura)
            if int(row["Effect"]) == TRIGGER_SPELL:
                for triggered in by_spell.get(int(row["EffectTriggerSpell"]), ()):
                    aura = int(triggered["EffectAura"])
                    if aura in (FOOD_AURA, DRINK_AURA):
                        found.add(aura)
        return found

    food, drink = set(), set()
    for row in item_x_item_effect:
        spell = use_spells.get(int(row["ItemEffectID"]))
        if spell is None:
            continue
        found = auras(spell)
        if FOOD_AURA in found:
            food.add(int(row["ItemID"]))
        if DRINK_AURA in found:
            drink.add(int(row["ItemID"]))
    return sorted(food), sorted(drink)


def skill_line_categories(skill_line):
    return {int(row["ID"]): int(row["CategoryID"]) for row in skill_line}


def profession_skill_spells(skill_line_ability, categories):
    """Learnt spell -> the profession or secondary skill lines it belongs to."""
    profession = {line for line, category in categories.items() if category in PROFESSION_CATEGORIES}
    learned = defaultdict(set)
    for row in skill_line_ability:
        line = int(row["SkillLine"])
        if line in profession:
            learned[int(row["Spell"])].add(line)
    return learned


def profession_items(items, skill_spells, spell_reagents, spell_totems):
    """Item -> the profession skill lines it supplies, from a recipe's RequiredSkill and a spell's reagent or totem."""
    result = defaultdict(set)
    for row in items:
        skill = int(row["RequiredSkill"] or 0)
        if skill in LEARNABLE_PROFESSIONS:
            result[int(row["ID"])].add(skill)
    for row in spell_reagents:
        lines = skill_spells.get(int(row["SpellID"]))
        if not lines:
            continue
        for index in range(8):
            item = int(row[f"Reagent_{index}"])
            if item and int(row[f"ReagentCount_{index}"]):
                result[item] |= {line for line in lines if line in LEARNABLE_PROFESSIONS}
    totem_lines = defaultdict(set)
    for row in spell_totems:
        lines = skill_spells.get(int(row["SpellID"]))
        if not lines:
            continue
        for index in (0, 1):
            category = int(row[f"RequiredTotemCategoryID_{index}"])
            if category:
                totem_lines[category] |= {line for line in lines if line in LEARNABLE_PROFESSIONS}
    for row in items:
        lines = totem_lines.get(int(row["TotemCategoryID"] or 0))
        if lines:
            result[int(row["ID"])] |= lines
    return {item: sorted(lines) for item, lines in result.items() if lines}


def vendor_item_professions(vendor_rows, item_professions):
    """Item -> the profession skill lines it supplies, for the items any vendor sells."""
    sold = {int(row["item"]) for row in vendor_rows}
    return {item: item_professions[item] for item in sorted(sold) if item in item_professions}


def profession_trainers(creatures, trainer_rows, template_rows, spell_effect, skill_spells):
    """TrainerType 2 NPC -> its one profession skill line, from the spells it teaches."""
    by_spell = defaultdict(list)
    for row in spell_effect:
        by_spell[int(row["SpellID"])].append(row)
    trainers, templates = defaultdict(set), defaultdict(set)
    for row in trainer_rows:
        trainers[int(row["entry"])].add(int(row["spell"]))
    for row in template_rows:
        templates[int(row["entry"])].add(int(row["spell"]))
    result = {}
    for creature in creatures:
        if int(creature["TrainerType"]) != 2:
            continue
        entry = int(creature["Entry"])
        spells = trainers.get(entry, set()) | templates.get(int(creature["TrainerTemplateId"]), set())
        lines = set()
        for spell in spells:
            for row in by_spell.get(spell, ()):
                if int(row["Effect"]) == LEARN_SPELL:
                    lines |= skill_spells.get(int(row["EffectTriggerSpell"]), set())
        if len(lines) > 1:
            raise ValueError(f"profession trainer {entry} ({creature['Name']}) teaches skill lines {sorted(lines)}")
        if lines:
            result[entry] = next(iter(lines))
    return dict(sorted(result.items()))


def class_trainers(creatures):
    """TrainerType 0 NPC -> the player class it trains. TrainerClass 0 is not a class."""
    result = {}
    for creature in creatures:
        if int(creature["TrainerType"]) != 0:
            continue
        class_id = int(creature["TrainerClass"])
        if class_id:
            result[int(creature["Entry"])] = class_id
    return dict(sorted(result.items()))


def portal_trainers(creatures, trainer_rows, template_rows, spell_rows, teleport_spells):
    """A mage class trainer whose every taught spell opens or lands at a destination: the client's portal trainers."""
    spells = {int(row["Id"]): row for row in spell_rows}

    def opens_or_lands(row, spell):
        if spell in teleport_spells:
            return True
        for index in (1, 2, 3):
            effect = int(row[f"Effect{index}"])
            trigger = int(row[f"EffectTriggerSpell{index}"])
            if effect == TRANS_DOOR or trigger in teleport_spells:
                return True
            learned = spells.get(trigger) if effect == LEARN_SPELL else None
            if learned and any(int(learned[f"Effect{at}"]) == TRANS_DOOR for at in (1, 2, 3)):
                return True
        return False

    def destination(spell):
        row = spells.get(spell)
        return row is not None and opens_or_lands(row, spell)

    trainers, templates = defaultdict(set), defaultdict(set)
    for row in trainer_rows:
        trainers[int(row["entry"])].add(int(row["spell"]))
    for row in template_rows:
        templates[int(row["entry"])].add(int(row["spell"]))
    result = {}
    for creature in creatures:
        if int(creature["TrainerType"]) != 0 or int(creature["TrainerClass"]) != MAGE:
            continue
        entry = int(creature["Entry"])
        taught = trainers.get(entry, set()) | templates.get(int(creature["TrainerTemplateId"]), set())
        if taught and all(destination(spell) for spell in taught):
            result[entry] = MAGE
    return dict(sorted(result.items()))


def battlemasters(creatures, rows):
    """Battlemaster NPC -> its battleground template, from the table that links the two."""
    known = {int(creature["Entry"]) for creature in creatures}
    result = {}
    for row in rows:
        entry = int(row["entry"])
        if entry in known:
            result[entry] = int(row["bg_template"])
    return dict(sorted(result.items()))


def render_array(values, depth=0, width=116):
    if not values:
        return "{ }"
    lines, line = [], ""
    for value in values:
        item = lua(value)
        if line and len(line) + len(item) + 2 + (depth + 1) * 4 > width:
            lines.append(line)
            line = ""
        line += (", " if line else "") + item
    lines.append(line)
    return "{\n" + "\n".join("\t" * (depth + 1) + part + "," for part in lines) + "\n" + "\t" * depth + "}"


def render_lists(table, width=116):
    """A table of [key] = { numbers }, one entry per column, packed to the file's width."""
    lines, line = [], ""
    for key, values in table.items():
        item = f"[{key}] = {{ {', '.join(lua(value) for value in values)} }},"
        if line and len(line) + len(item) + 5 > width:
            lines.append(line)
            line = ""
        line += (" " if line else "") + item
    lines.append(line)
    return "{\n" + "\n".join("\t" + part for part in lines) + "\n}"


def header(source):
    return [
        "-- Generated by tools/gen_services.py - do not edit.",
        f"-- Source: {source}",
        f"-- DB2: https://wago.tools/db2 (CSV build {BUILD}).",
        f"-- DB: https://github.com/cmangos/classic-db/tree/{DB_REV}",
        "---@type string, SPFNamespace",
        "local _, ns = ...",
        "",
    ]


def assignment(name, value):
    return ["-- stylua: ignore", name + " = " + value, ""]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload pinned sources")
    mode.add_argument("--offline", action="store_true", help="use cached sources only")
    args = parser.parse_args()
    tables = {
        name: db2(name, args.refresh, args.offline)
        for name in (
            "ItemSparse",
            "ItemXItemEffect",
            "ItemEffect",
            "SpellEffect",
            "SpellReagents",
            "SpellTotems",
            "SkillLine",
            "SkillLineAbility",
        )
    }
    db = classicdb(args.refresh, args.offline)
    creatures = db["creature_template"]
    trainers = db["npc_trainer"]
    templates = db["npc_trainer_template"]
    food, drink = food_and_drink(tables["ItemXItemEffect"], tables["ItemEffect"], tables["SpellEffect"])
    categories = skill_line_categories(tables["SkillLine"])
    skill_spells = profession_skill_spells(tables["SkillLineAbility"], categories)
    professions = profession_trainers(creatures, trainers, templates, tables["SpellEffect"], skill_spells)
    classes = class_trainers(creatures)
    teleports = {int(row["id"]) for row in db["spell_target_position"]}
    portals = portal_trainers(creatures, trainers, templates, db["spell_template"], teleports)
    battlemasters_by_npc = battlemasters(creatures, db["battlemaster_entry"])
    item_professions = profession_items(
        tables["ItemSparse"], skill_spells, tables["SpellReagents"], tables["SpellTotems"]
    )
    supplies = vendor_item_professions(db["npc_vendor"], item_professions)
    lines = header(
        "DB2 item, spell and skill-line tables; classic-db creature, trainer, battlemaster, vendor and spell tables."
    )
    lines += [
        "-- Food: items whose use spell has a MOD_REGEN aura (84); Drink: MOD_POWER_REGEN (85), one TRIGGER_SPELL",
        "-- (64) hop included. An item can be both.",
        "-- ProfessionTrainers: [npc] = skill line (CategoryID 11 or 9) of the spells a TrainerType 2 NPC teaches.",
        "-- ClassTrainers: [npc] = TrainerClass of a TrainerType 0 trainer; TrainerClass 0 is not a class.",
        "-- PortalTrainers: [npc] = class of a mage trainer whose every taught spell opens or lands at a destination.",
        "-- Battlemasters: [npc] = battleground template, from classic-db battlemaster_entry.",
        "-- ItemProfessions: [item] = the profession skill lines its goods supply, from a recipe's RequiredSkill and",
        "-- the reagents and tools or totems a profession's spells use, for the items a vendor sells. An item with",
        "-- none is absent: it serves every character.",
        "",
    ]
    lines += assignment("ns.Food", render_array(food))
    lines += assignment("ns.Drink", render_array(drink))
    lines += assignment("ns.ProfessionTrainers", render(professions))
    lines += assignment("ns.ClassTrainers", render(classes))
    lines += assignment("ns.PortalTrainers", render(portals))
    lines += assignment("ns.Battlemasters", render(battlemasters_by_npc))
    lines += assignment("ns.ItemProfessions", render_lists(supplies))
    publish({ROOT / "Data" / "Services.lua": "\n".join(lines)})
    print(
        f"Services: {len(food)} food, {len(drink)} drink, {len(professions)} profession trainers, "
        f"{len(classes)} class trainers, {len(portals)} portal trainers, "
        f"{len(battlemasters_by_npc)} battlemasters, {len(supplies)} vendor items for professions"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, urllib.error.URLError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
