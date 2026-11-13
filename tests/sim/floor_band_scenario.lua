-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
-- Stormwind Keep: the client's range checks to a guard whose GUID names it bound the player's height to the Keep's
-- floor and not the ground 46 yards under it (#737, #602). What a walk does with that band is tests/band_spec.lua's,
-- a map search needing the walking maps this client model cannot decode.
scenario(
	"range checks to an NPC named by its GUID bound the player's height",
	{ addons = ForeverCore.addons() },
	function(sim)
		local player = sim.world.player
		player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
		player.map, player.x, player.y = 1453, 0.5, 0.5
		sim:login()
		local ns
		for _, entry in ipairs(sim.loader.addons) do
			if entry.name == ADDON then
				ns = entry.ns
			end
		end
		assert(ns, "full addon namespace loaded")

		-- The client: the player on the Keep's floor, a guard standing still at the spawn Data/IdleSpawns.lua holds for
		-- its creature ID, and the player's spells whose ranges the client reports. A range check measures the 3D
		-- distance to the player's real height, which no addon call sees.
		local HERE = { x = -9020, y = 870, z = 152 } -- Keep: surfaces at 106, 112 and 152 yd
		local GUARD = 5694 -- its idle spawn, 11.4 yd off at (-9011, 877, 148)
		local CREATURE = string.format("Creature-0-0-0-0-%d-0000000001", GUARD)
		-- Arcane Intellect's ranks target an ally, Hunter's Mark targets any unit and Fireball targets an enemy: the
		-- generated tables keep them for the friendly or hostile ladder.
		local known = { 1459, 1460, 1461, 1130, 133 }
		local ranges = { [1459] = 10, [1460] = 30, [1461] = 40, [1130] = 30, [133] = 35 }
		-- The guard is the target and carries a nameplate, the two tokens a nearby NPC is read through.
		local units = { target = GUARD, nameplate1 = GUARD }
		local itemAsks = 0

		sim.impl["C_SpellBook.GetNumSpellBookSkillLines"] = function()
			return 1
		end
		sim.impl["C_SpellBook.GetSpellBookSkillLineInfo"] = function()
			return { itemIndexOffset = 0, numSpellBookItems = #known }
		end
		sim.impl["C_SpellBook.GetSpellBookItemInfo"] = function(slot)
			return { spellID = known[slot] }
		end
		sim.impl["C_Spell.GetSpellInfo"] = function(id)
			return { name = "Spell", iconID = 1, originalIconID = 1, castTime = 0, minRange = 0, maxRange = ranges[id] }
		end
		local function hostile(unit)
			local target = sim.world.units[unit]
			return target ~= nil and target.friendly == false
		end
		sim.impl["C_Spell.IsSpellInRange"] = function(id, unit)
			if not (units[unit] and ranges[id]) then
				return nil
			end
			if (hostile(unit) and not ns.HostileSpells[id]) or (not hostile(unit) and not ns.SpellTargets[id]) then
				return nil
			end
			local dx, dy, dz = -9011 - HERE.x, 877 - HERE.y, 148 - HERE.z
			return dx * dx + dy * dy + dz * dz <= ranges[id] * ranges[id]
		end
		sim.impl["C_Item.IsItemInRange"] = function(id, unit)
			itemAsks = itemAsks + 1
			local entry = ns.BandItems[id]
			if not (units[unit] and entry) then
				return nil
			end
			if (hostile(unit) and not entry.hostile) or (not hostile(unit) and not entry.friendly) then
				return nil
			end
			local dx, dy, dz = -9011 - HERE.x, 877 - HERE.y, 148 - HERE.z
			return dx * dx + dy * dy + dz * dz <= entry.range * entry.range
		end
		sim.impl["C_NamePlate.GetNamePlates"] = function()
			return { { namePlateUnitToken = "nameplate1" } }
		end
		sim.world.units.target = {
			name = "Stormwind Guard",
			level = 60,
			friendly = true,
			guid = CREATURE,
		}
		sim.world.units.nameplate1 = {
			name = "Stormwind Guard",
			level = 60,
			friendly = true,
			guid = CREATURE,
		}

		sim:input(function()
			local band = assert(ns.Band.At(0, HERE.x, HERE.y), "the guard's range check bounds the height")
			assert(band.lo > 106 and band.hi >= 152, "the band holds the Keep's floor: " .. band.lo .. ".." .. band.hi)
			assert(ns.Band.Holds(band, 150), "and the Keep's walkway")
			assert(not ns.Band.Holds(band, 106), "but not the ground under it")
			assert(not ns.Band.Holds(band, 112), "nor the ledge between")
			-- Walked away from the guard, the band is gone rather than kept on a guess.
			assert(ns.Band.At(0, HERE.x + 60, HERE.y) == nil, "out of the guard's range, nothing is measured")
			assert(ns.Band.At(0, HERE.x, HERE.y), "and back beside it, measured again")
		end)

		sim:input(function()
			-- A carried bandage adds its on-use spell's 15 yd range to the ladder, so a friendly NPC is measured by an
			-- item as well as by a spell.
			sim.world.items[1251] = { name = "Linen Bandage", count = 1 }
			ns.Band.Forget()
			local before = itemAsks
			local band = assert(ns.Band.At(0, HERE.x, HERE.y), "the carried bandage answers")
			assert(itemAsks > before, "the item ladder asked the carried bandage")
			assert(band.lo > 106 and band.hi >= 152, "the item's bound holds the Keep's floor")
			assert(not ns.Band.Holds(band, 106), "and not the ground under it")
		end)

		sim:input(function()
			-- A stationary hostile NPC with one idle spawn counts too: Hunter's Mark targets any unit and Fireball an
			-- enemy, while the bandage targets an ally and is not asked of it.
			sim.world.units.target.friendly = false
			sim.world.units.nameplate1.friendly = false
			ns.Band.Forget()
			local before = itemAsks
			local band = assert(ns.Band.At(0, HERE.x, HERE.y), "the hostile guard answers an any-target spell")
			assert(itemAsks == before, "a friendly-only bandage is not asked of a hostile NPC")
			assert(band.lo > 106 and band.hi >= 152, "the hostile guard's bound holds the Keep's floor")
			assert(not ns.Band.Holds(band, 106), "but not the ground under it")
			sim.world.units.target.friendly = true
			sim.world.units.nameplate1.friendly = true
		end)

		sim:input(function()
			-- A creature with two idle spawns on this map is not measured: which spawn the client's answer is about is
			-- unknown, so the nearest one is no standing-in.
			ns.IdleSpawns[0][5697] = "-9011 877 148 -9020 900 148"
			sim.world.units.target.guid = "Creature-0-0-0-0-5697-0000000001"
			sim.world.units.nameplate1 = nil
			ns.Band.Forget()
			assert(ns.Band.At(0, HERE.x, HERE.y) == nil, "two spawns leave no single height to bound")

			-- A GUID the client withholds is no identification either.
			ns.IdleSpawns[0][5697] = nil
			sim.world.units.target.guid = CREATURE
			local realGUID = sim.impl.UnitGUID
			sim.impl.UnitGUID = function(unit)
				if unit == "target" then
					return sim.secret.wrap(CREATURE)
				end
				return realGUID(unit)
			end
			ns.Band.Forget()
			assert(ns.Band.At(0, HERE.x, HERE.y) == nil, "a secret GUID measures nothing")
			sim.impl.UnitGUID = realGUID
			ns.Band.Forget()
			assert(ns.Band.At(0, HERE.x, HERE.y), "the readable GUID measures again")
		end)
		sim:expectNoErrors(ADDON)
	end
)
