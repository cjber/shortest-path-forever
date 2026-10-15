local ns = {}
assert(loadfile("Data/Teleports.lua"))("ShortestPathForever", ns)

local bySpell = {}
for _, teleport in ipairs(ns.Teleports) do
	assert(not bySpell[teleport.spell], "one entry per spell")
	assert(teleport.cast > 0, "every teleport has a cast time")
	assert((teleport.bind == true) ~= (teleport.to ~= nil), "a teleport lands at the bind point or a sourced place")
	bySpell[teleport.spell] = teleport
end

-- UiMapAssignment 1450 (Moonglade) and 1453 (Stormwind City) bounds at build 1.60.1.69913.
local function within(point, map, minX, maxX, minY, maxY)
	return point.map == map and point.x >= minX and point.x <= maxX and point.y >= minY and point.y <= maxY
end
assert(within(bySpell[18960].to, 1, 6952.08, 8491.67, -3689.58, -1381.25), "Teleport: Moonglade lands in Moonglade")
assert(not bySpell[18960].reagents, "Teleport: Moonglade needs no reagent")
assert(within(bySpell[3561].to, 0, -9154.17, -7995.83, -14.58, 1722.92), "Teleport: Stormwind lands in Stormwind")
assert(bySpell[3561].reagents[17031] == 1, "mage teleports use a Rune of Teleportation")
assert(bySpell[8690].item == 6948 and bySpell[8690].bind, "the Hearthstone returns you to your bind point")
assert(bySpell[556].bind and not bySpell[556].item, "Astral Recall is a shaman spell to the bind point")
assert(not bySpell[1297659], "Teleport: Dalaran has no sourced destination")
assert(not bySpell[23442], "the Everlook ripper is not a personal teleport")

-- The planner: a teleport is an edge from where you stand, its remaining cooldown a wait.
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)
local Plan = ns.Planner.Plan

-- 7000 yards on foot is 1000 s; the hearth lands 70 yards short of the goal (10 s) after a 10 s cast.
local hearths = { { map = 1, x = 6930, y = 0, spell = 8690, item = 6948, cast = 10000, label = "Goldshire" } }
local function trip(ready, cache, minimum)
	return Plan({
		cache = cache,
		from = { map = 1, x = 0, y = 0 },
		to = { map = 1, x = 7000, y = 0 },
		now = 1000,
		walkSpeed = 7,
		teleports = hearths,
		teleportReady = ready and { ready } or nil,
		hearthMinimumSavings = minimum,
	})
end

local hearthed = trip(1000)
assert(#hearthed.legs == 2 and hearthed.legs[1].mode == "teleport", "the hearth beats a long walk")
local cast = hearthed.legs[1]
assert(cast.teleport.item == 6948 and cast.wait == 0 and cast.arrive == 11000 and cast.ready == 1000)
assert(cast.to.kind == "teleport" and cast.to.label == "Goldshire")
assert(hearthed.legs[2].mode == "walk" and hearthed.legs[2].from == cast.to, "walk on from where it lands")
assert(ns.Planner.LegPoints(cast, {})[1].jump, "no line is drawn across the world")

local waited = trip(1000 + 300000)
assert(waited.legs[1].mode == "teleport" and waited.legs[1].wait == 300000, "a cooldown shorter than the walk waits")
assert(trip(1000 + 2000000).legs[1].mode == "walk", "a cooldown longer than the walk is ignored")
assert(trip(nil).legs[1].mode == "walk", "a teleport that cannot be cast is ignored")

-- The same topology serves a new cooldown: readiness is per plan, never a rebuild.
local cache = {}
assert(trip(1000, cache).legs[1].mode == "teleport")
local topology = cache.topology
assert(trip(1000 + 2000000, cache).legs[1].mode == "walk" and cache.topology == topology)
assert(trip(1000, cache).legs[1].mode == "teleport" and cache.topology == topology)
assert(trip(1000, cache, 980).legs[1].mode == "teleport", "saving exactly the threshold allows Hearthstone")
assert(trip(1000, cache, 981).legs[1].mode == "walk", "a smaller saving preserves Hearthstone")
assert(cache.topology == topology, "the non-hearth comparison reuses topology")
assert(trip(301000, cache, 680).legs[1].mode == "teleport", "the threshold includes cooldown waiting")
assert(trip(301000, cache, 681).legs[1].mode == "walk", "cooldown can push savings below the threshold")
local alternatives = Plan({
	from = { map = 1, x = 0, y = 0 },
	to = { map = 1, x = 7000, y = 0 },
	now = 0,
	walkSpeed = 7,
	teleports = { hearths[1], { map = 1, x = 7000, y = 0, spell = 3566, cast = 30000 } },
	teleportReady = { 0, 0 },
	hearthMinimumSavings = 11,
})
assert(alternatives.legs[1].teleport.spell == 3566, "class teleports remain an alternative to Hearthstone")
assert(alternatives.arrive == 30000, "no invented savings penalty enters the ETA")
-- A new set of destinations (a new bind point) is a new topology.
hearths = { { map = 1, x = -700, y = 0, spell = 8690, item = 6948, cast = 10000 } }
assert(trip(1000, cache).legs[1].mode == "walk" and cache.topology ~= topology)

-- Another continent adds the loading screen.
local far = Plan({
	from = { map = 0, x = 0, y = 0 },
	to = { map = 1, x = 7000, y = 0 },
	now = 0,
	teleports = { { map = 1, x = 7000, y = 0, spell = 3566, cast = 10000 } },
	teleportReady = { 0 },
})
assert(#far.legs == 1 and far.legs[1].arrive == 15000)
local onlyHearth = Plan({
	from = { map = 0, x = 0, y = 0 },
	to = { map = 1, x = 7000, y = 0 },
	now = 0,
	teleports = { { map = 1, x = 7000, y = 0, spell = 8690, item = 6948, cast = 10000 } },
	teleportReady = { 0 },
	hearthMinimumSavings = 600,
})
assert(onlyHearth and onlyHearth.arrive == 15000, "retain Hearthstone when no alternative reaches the destination")

-- What this character can cast, read from the client.
do
	local secret = {}
	local items, spells, cooldowns, itemCooldowns, casts = {}, {}, {}, {}, {}
	local bindName, position, onEvent = "Goldshire", { 10, 20, 30, 0 }, nil
	local timers, registered = {}, {}
	-- Runs the timers due now; the ones they schedule wait for the next tick.
	local function tick()
		local due = timers
		timers = {}
		for _, fn in ipairs(due) do
			fn()
		end
	end
	local runtime = { db = { teleports = true }, charDB = {}, Teleports = ns.Teleports }
	runtime.Init = function(fn)
		fn()
	end
	runtime.JourneyPosition = function()
		return unpack(position)
	end
	local env = setmetatable({
		C_Item = {
			GetItemCount = function(id)
				return items[id] or 0
			end,
			GetItemCooldown = function(id)
				return unpack(itemCooldowns[id] or { 0, 0, true })
			end,
		},
		C_SpellBook = {
			IsSpellKnown = function(id)
				return spells[id] or false
			end,
		},
		C_Spell = {
			GetSpellInfo = function(id)
				return casts[id] and { castTime = casts[id] }
			end,
			GetSpellCooldown = function(id)
				return cooldowns[id] or { startTime = 0, duration = 0 }
			end,
		},
		GetBindLocation = function()
			return bindName
		end,
		GetTime = function()
			return 100
		end,
		canaccessvalue = function(value)
			return value ~= secret
		end,
		C_Timer = {
			After = function(_, fn)
				timers[#timers + 1] = fn
			end,
		},
		CreateFrame = function()
			return {
				RegisterEvent = function(_, event)
					registered[event] = true
				end,
				RegisterUnitEvent = function(_, event, unit)
					assert(unit == "player")
					registered[event] = true
				end,
				SetScript = function(_, _, fn)
					onEvent = fn
				end,
			}
		end,
	}, { __index = _G })
	setfenv(assert(loadfile("Transport/Teleports.lua")), env)("ShortestPathForever", runtime)
	local Usable = runtime.UsableTeleports

	local places, ready = Usable(5000)
	assert(#places == 0 and next(ready) == nil, "nothing known, nothing usable")

	spells[3561] = true
	places, ready = Usable(5000)
	assert(#places == 1 and places[1].spell == 3561 and places[1].map == 0, "a known teleport is a place")
	assert(not ready[1], "without its rune it cannot be cast")
	items[17031] = 1
	local same
	same, ready = Usable(5000)
	assert(same == places and ready[1] == 5000, "the same places, now ready")
	cooldowns[3561] = { startTime = 90, duration = 60 }
	assert(select(2, Usable(5000))[1] == 55000, "the cooldown left delays it")
	cooldowns[3561] = { startTime = secret, duration = secret }
	assert(not select(2, Usable(5000))[1], "a secret cooldown is never guessed")
	cooldowns[3561], spells[3561] = nil, nil
	-- The cast time is the client's own where it reports one, and the shipped one where it does not.
	assert(places[1].cast == 10000, "the shipped cast time")
	casts[3562], spells[3562] = 8500, true
	assert(Usable(5000)[1].cast == 8500, "the client's cast time")
	casts[3562] = secret
	spells[3561] = true
	places = Usable(5000)
	assert(places[2].spell == 3562 and places[2].cast == 10000, "a secret cast time is never used")
	casts[3562], spells[3561], spells[3562] = nil, nil, nil

	items[6948] = 1
	assert(#Usable(5000) == 0, "no hearth before a bind point is recorded")
	onEvent(nil, "HEARTHSTONE_BOUND")
	local bind = runtime.charDB.bind
	assert(bind.name == "Goldshire" and bind.map == 0 and bind.x == 10 and bind.y == 20 and bind.z == 30)
	places, ready = Usable(5000)
	assert(#places == 1 and places[1].item == 6948 and places[1].x == 10 and places[1].label == "Goldshire")
	assert(ready[1] == 5000)
	runtime.db.teleports = false
	assert(#Usable(5000) == 0 and next((select(2, Usable(5000)))) == nil, "the setting off hides every teleport")
	runtime.db.teleports = true
	assert(Usable(5000) == places, "and on again, the same places")
	itemCooldowns[6948] = { 50, 3600, true }
	assert(select(2, Usable(5000))[1] == 5000 + 3550000, "the hearth's own cooldown")
	bindName = "Razor Hill"
	assert(#Usable(5000) == 0, "bound elsewhere since: no bind teleport")
	position = {}
	onEvent(nil, "HEARTHSTONE_BOUND")
	assert(runtime.charDB.bind == nil, "no position, no bind point")

	-- A new install never saw the rebind: the Hearthstone's landing is the bind point.
	assert(registered.UNIT_SPELLCAST_SUCCEEDED and registered.PLAYER_ENTERING_WORLD and registered.HEARTHSTONE_BOUND)
	bindName, position = "Razor Hill", { 100, 100, 5, 1 }
	onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8690)
	assert(runtime.charDB.bind == nil, "not landed yet")
	tick()
	assert(runtime.charDB.bind == nil, "still where it was cast")
	position = { 300, 900, 12, 1 }
	tick()
	bind = runtime.charDB.bind
	assert(bind and bind.name == "Razor Hill" and bind.map == 1 and bind.x == 300 and bind.y == 900 and bind.z == 12)
	assert(#timers == 0, "landed: no more looks")
	assert(#Usable(5000) == 1 and Usable(5000)[1].x == 300, "the hearth goes where it landed")

	-- Another continent: the loading screen's end finds the landing.
	runtime.charDB.bind = nil
	position = { 300, 900, 12, 1 }
	onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 556)
	position = { 300, 900, 12, 0 }
	onEvent(nil, "PLAYER_ENTERING_WORLD")
	assert(runtime.charDB.bind and runtime.charDB.bind.map == 0, "Astral Recall to another continent")
	tick()
	assert(#timers == 0)

	-- Other spells, a bind point renamed mid-flight and a landing that never comes record nothing.
	runtime.charDB.bind = nil
	onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 3561)
	assert(#timers == 0, "not a bind teleport")
	onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", secret)
	assert(#timers == 0, "a secret spell is never guessed")
	onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 8690)
	bindName, position = "Goldshire", { 5000, 5000, 0, 0 }
	tick()
	assert(runtime.charDB.bind == nil and #timers == 0, "bound elsewhere since the cast")
	position = { 300, 900, 12, 0 }
	onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6", 8690)
	for _ = 1, 40 do
		tick()
	end
	assert(runtime.charDB.bind == nil and #timers == 0, "it gives up when nothing moves")
	position = { 9000, 9000, 0, 0 }
	onEvent(nil, "PLAYER_ENTERING_WORLD")
	assert(runtime.charDB.bind == nil, "a later move is not a landing")

	-- A real rebind while a landing is awaited wins.
	position = { 300, 900, 12, 0 }
	onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-7", 8690)
	onEvent(nil, "HEARTHSTONE_BOUND")
	position = { 9000, 9000, 0, 0 }
	tick()
	assert(runtime.charDB.bind.x == 300, "the rebind stands")
	items[6948] = 0
end

print("teleports_spec: ok")
