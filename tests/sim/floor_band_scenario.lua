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
		-- its creature ID, and three of the player's spells whose ranges the client reports. A range check measures the
		-- 3D distance to the player's real height, which no addon call sees.
		local HERE = { x = -9020, y = 870, z = 152 } -- Keep: surfaces at 106, 112 and 152 yd
		local GUARD = 5694 -- its idle spawn, 11.4 yd off at (-9011, 877, 148)
		local CREATURE = string.format("Creature-0-0-0-0-%d-0000000001", GUARD)
		local ranges = { 10, 30, 40 }
		-- The guard is the target and carries a nameplate, the two tokens a nearby NPC is read through.
		local units = { target = GUARD, nameplate1 = GUARD }

		sim.impl["C_SpellBook.GetNumSpellBookSkillLines"] = function()
			return 1
		end
		sim.impl["C_SpellBook.GetSpellBookSkillLineInfo"] = function()
			return { itemIndexOffset = 0, numSpellBookItems = #ranges }
		end
		sim.impl["C_SpellBook.GetSpellBookItemInfo"] = function(slot)
			return { spellID = slot }
		end
		sim.impl["C_Spell.GetSpellInfo"] = function(id)
			return { name = "Spell", iconID = 1, originalIconID = 1, castTime = 0, minRange = 0, maxRange = ranges[id] }
		end
		sim.impl["C_Spell.IsSpellInRange"] = function(id, unit)
			if not (units[unit] and ranges[id]) then
				return nil
			end
			local dx, dy, dz = -9011 - HERE.x, 877 - HERE.y, 148 - HERE.z
			return dx * dx + dy * dy + dz * dz <= ranges[id] * ranges[id]
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
