-- The quick Use Hearthstone switch (#707): the saved flag keeps only the Hearthstone out of journeys, the tracker's
-- journey menu and the world map's innkeeper button flip it, a flip replans the journey, and the button's tooltip
-- describes saving it for later.
local function check(value, label)
	assert(value, label)
end

-- Transport/Teleports.lua, with the client's item, spell and bind answers stubbed.
do
	local ns = {}
	assert(loadfile("Data/Teleports.lua"))("ShortestPathForever", ns)

	local secret = {}
	local items, spells, cooldowns, itemCooldowns, casts = {}, {}, {}, {}, {}
	local bindName, position, onEvent = "Goldshire", { 10, 20, 30, 0 }, nil
	local registered, clock, travelTick = {}, 100, nil
	local runtime = { db = { teleports = true, useHearthstone = true }, charDB = {}, Teleports = ns.Teleports }
	runtime.Init = function(fn)
		fn()
	end
	runtime.JourneyPosition = function()
		return position[1], position[2], nil, position[4]
	end
	runtime.OnTravelTick = function(fn)
		travelTick = fn
	end
	runtime.WakeTravel = function() end
	local function tick()
		clock = clock + 1
		travelTick()
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
			return clock
		end,
		canaccessvalue = function(value)
			return value ~= secret
		end,
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
	local Usable, Hearthstone = runtime.UsableTeleports, runtime.Hearthstone

	-- A known class teleport, with its rune, and the Hearthstone in the bags. The bind point is known from a rebind.
	spells[3561], items[17031], items[6948] = true, 1, 1
	onEvent(nil, "HEARTHSTONE_BOUND")
	local places = assert(Usable(5000))
	check(#places == 2, "a known class teleport and the Hearthstone are both usable")
	check(places[1].spell == 3561 and places[2].item == 6948, "the class teleport stays beside the Hearthstone")

	-- The switch off keeps only the Hearthstone out.
	runtime.db.useHearthstone = false
	places = assert(Usable(5000))
	check(#places == 1 and places[1].spell == 3561, "the switch leaves class teleports alone")
	runtime.db.useHearthstone = true
	check(#assert(Usable(5000)) == 2, "and on again, the Hearthstone is back")

	-- Class teleports have their own switch, and it leaves the bind teleports alone.
	runtime.db.teleports = false
	places = assert(Usable(5000))
	check(#places == 1 and places[1].item == 6948, "class teleports off keeps the Hearthstone")
	runtime.db.useHearthstone = false
	check(#Usable(5000) == 0, "both switches off have nothing to offer")
	runtime.db.teleports, runtime.db.useHearthstone = true, true
	check(#assert(Usable(5000)) == 2, "both on again, both are back")

	-- The Hearthstone lookup stays available independently of the journey setting.
	local hearth = assert(Hearthstone(5000))
	check(hearth.name == "Goldshire" and hearth.map == 0 and hearth.x == 10 and hearth.y == 20, "the bind point")
	check(hearth.place.item == 6948 and hearth.readyAt == 5000, "the Hearthstone's own place, ready now")
	runtime.db.useHearthstone = false
	check(Hearthstone(5000) ~= nil, "the lookup still knows where the Hearthstone goes")
	runtime.db.teleports = false
	check(Hearthstone(5000) ~= nil, "class teleports off still leaves the Hearthstone lookup")
	runtime.db.teleports = true
	items[6948] = 0
	onEvent(nil, "BAG_UPDATE_DELAYED")
	check(Hearthstone(5000) == nil, "without the Hearthstone, no button")
	items[6948] = 1
	itemCooldowns[6948] = { 50, 3600, true }
	onEvent(nil, "BAG_UPDATE_DELAYED")
	onEvent(nil, "BAG_UPDATE_COOLDOWN")
	check(assert(Hearthstone(5000)).readyAt == 5000 + 3550000, "the Hearthstone's cooldown is its readiness")
	tick()
	check(registered.HEARTHSTONE_BOUND and registered.PLAYER_ENTERING_WORLD, "the bind events are watched")
end

-- The journey: a flip replans, the hearth leg leaves, and the class teleport still carries the journey.
do
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local ns = driver.ns
	local hearth = { map = 1, x = 6930, y = 0, spell = 8690, item = 6948, bind = true, cast = 10000 }
	local class = { map = 1, x = 3500, y = 0, spell = 3561, cast = 10000 }
	ns.teleports, ns.teleportReady = { class, hearth }, { 0, 0 }
	-- What Transport/Teleports.lua returns: each switch allows its own kind of teleport.
	ns.UsableTeleports = function()
		local places, ready = {}, {}
		for index, teleport in ipairs(ns.teleports) do
			local wanted = teleport.bind and ns.db.useHearthstone ~= false or ns.db.teleports ~= false
			if wanted then
				places[#places + 1] = teleport
				ready[#places] = ns.teleportReady[index]
			end
		end
		return places, ready
	end
	local origin, destination = { map = 1, x = 0, y = 0 }, { map = 1, x = 7000, y = 0 }
	local policy = ns.TravelPolicyChanged
	local policies = 0
	ns.TravelPolicyChanged = function(...)
		policies = policies + 1
		return policy(...)
	end

	driver.begin(origin, destination)
	local planned = assert(driver.shown())
	check(planned.legs[1].teleport and planned.legs[1].teleport.item == 6948, "the journey starts with the Hearthstone")
	check(ns.HearthstoneEnabled(), "the switch starts on")

	-- A Hearthstone step skipped by hand is forgiven when the player turns the switch back on.
	check(ns.SkipJourneyStep(1), "the Hearthstone step can be completed by hand")
	check(ns.JourneyWithoutHearth(), "a completed step refuses it for this journey")

	ns.SetHearthstoneEnabled(false)
	check(not ns.HearthstoneEnabled() and ns.db.useHearthstone == false, "the toggle saves the switch off")
	check(policies == 1, "the toggle invalidates the travel policy")
	driver.update(5)
	for _, leg in ipairs(assert(driver.shown()).legs) do
		check(not (leg.teleport and leg.teleport.item == 6948), "the Hearthstone is out of the replanned journey")
	end
	local classed = false
	for _, leg in ipairs(assert(driver.shown()).legs) do
		classed = classed or (leg.teleport and leg.teleport.spell == 3561)
	end
	check(classed, "class teleports still carry the journey")

	ns.SetHearthstoneEnabled(true)
	check(ns.HearthstoneEnabled() and ns.db.useHearthstone == true, "the toggle saves the switch on")
	check(not ns.JourneyWithoutHearth(), "turning it on forgives the step skipped by hand")
	check(policies == 2, "the second flip invalidates the travel policy too")
	driver.update(5)
	planned = assert(driver.shown())
	check(planned.legs[1].teleport and planned.legs[1].teleport.item == 6948, "the Hearthstone is planned with again")

	-- The class teleport switch takes only the class teleport out of the journey.
	ns.db.teleports = false
	ns.TravelPolicyChanged()
	driver.update(5)
	planned = assert(driver.shown())
	check(
		planned.legs[1].teleport and planned.legs[1].teleport.item == 6948,
		"class teleports off still plans the Hearthstone"
	)
	for _, leg in ipairs(planned.legs) do
		check(not (leg.teleport and leg.teleport.spell == 3561), "the class teleport is out of the journey")
	end
	ns.db.teleports = true
	ns.TravelPolicyChanged()
	driver.update(5)

	-- Astral Recall is a bind teleport too, so skipping its step refuses it like the Hearthstone.
	local recall = { map = 1, x = 6930, y = 0, spell = 556, bind = true, cast = 10000 }
	ns.teleports, ns.teleportReady = { recall }, { 0 }
	-- A goal a yard away is a new journey, so the previous plan is not carried over.
	driver.begin(origin, { map = 1, x = 7001, y = 0 })
	planned = assert(driver.shown())
	check(planned.legs[1].teleport and planned.legs[1].teleport.spell == 556, "the journey starts with Astral Recall")
	check(ns.SkipJourneyStep(1), "the Astral Recall step can be completed by hand")
	check(ns.JourneyWithoutHearth(), "a completed Astral Recall step refuses it for this journey")
end

-- The map button, its tooltip and visibility, without a client frame.
do
	local answers = { enabled = true }
	local looked = {}
	local sharedPlaces, planCalls = {}, 0
	local runs = {}
	local standX = 0
	-- The journey keeps one goal table while it lasts.
	local journeyGoal = { map = 1, x = 100, y = 100 }
	local function pump()
		while #runs > 0 do
			local job = table.remove(runs, 1)
			if not job.cancelled then
				local a = job.fn(job)
				job.done = true
				job.callback(a)
			end
		end
	end
	local acquired, active, released = 0, 0, 0
	local pool = {
		ReleaseAll = function()
			released = released + active
			active = 0
		end,
		Acquire = function(_, hearth, x, y)
			check(hearth.map == 1 and x == 0.4 and y == 0.6, "the pin uses the bind point on the shown map")
			acquired, active = acquired + 1, active + 1
		end,
	}
	local ns = {
		L = setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		}),
		Canvas = {
			PinMixin = {},
			Pool = function()
				return pool
			end,
			Watch = function() end,
		},
		Init = function(fn)
			fn()
		end,
		JourneyMapPosition = function(_, mapID)
			check(mapID == 1, "the visible map is used")
			return 0.4, 0.6
		end,
		OpenMapAddon = {
			Stitched = function()
				return false
			end,
		},
		SetStopLook = function(_, kind, size)
			looked[#looked + 1] = { kind = kind, size = size }
			return true
		end,
		HearthstoneEnabled = function()
			return answers.enabled
		end,
		FormatCountdown = function(ms)
			local seconds = math.max(0, math.ceil(ms / 1000))
			return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
		end,
		JourneyGoal = function()
			return journeyGoal
		end,
		JourneyPosition = function()
			return standX, 0, nil, 1
		end,
		NowMs = function()
			return 1000
		end,
		Hearthstone = function()
			return {
				name = "Goldshire",
				map = 1,
				x = 10,
				y = 20,
				place = { map = 1, x = 10, y = 20, item = 6948, spell = 8690, bind = true, cast = 10000 },
				readyAt = 1000,
			}
		end,
		PlanContext = {
			Options = function()
				return { now = 1000, teleports = sharedPlaces, teleportReady = {} }
			end,
		},
		Path = {
			-- The path queue: a plan runs on a later frame, never in the frame that asked.
			Run = function(fn, callback)
				local job = { fn = fn, callback = callback }
				runs[#runs + 1] = job
				return job
			end,
			Cancel = function(job)
				job.cancelled = true
			end,
		},
		Planner = {
			Plan = function(options)
				planCalls = planCalls + 1
				return { arrive = options.withoutHearth and 20000 or 15000 }
			end,
		},
		JourneyWaterWalking = function()
			return false
		end,
	}
	local env = setmetatable({
		WorldMapFrame = {
			IsVisible = function()
				return true
			end,
			GetMapID = function()
				return 1
			end,
		},
		hooksecurefunc = function() end,
		CreateFromMixins = function(mixin)
			return setmetatable({}, { __index = mixin })
		end,
		InCombatLockdown = function()
			return false
		end,
	}, { __index = _G })
	setfenv(assert(loadfile("UI/HearthPin.lua")), env)("ShortestPathForever", ns)

	ns.RefreshHearthPin()
	check(acquired == 1 and active == 1, "enabled Hearthstone acquires one map pin")
	answers.enabled = false
	ns.RefreshHearthPin()
	check(acquired == 1 and active == 0, "disabled Hearthstone acquires no map pin")
	check(released == 1, "turning Hearthstone off releases its map pin")
	ns.RefreshHearthPin()
	check(acquired == 1 and active == 0, "Hearthstone stays absent while disabled")
	answers.enabled = true

	-- The comparison plans the same journey with and without the Hearthstone, without leaking it into the planner's
	-- shared place list (which Transport/Teleports.lua keeps between calls).
	local answered = 0
	check(ns.HearthSaving(function()
		answered = answered + 1
	end) == nil and planCalls == 0, "hovering plans nothing in its own frame")
	check(ns.HearthSaving() == nil and #runs == 1, "a second ask joins the comparison being planned")
	pump()
	check(answered == 1, "the answer calls back once it lands")
	check(ns.HearthSaving() == 5000, "the comparison measures the journey with and without the Hearthstone")
	check(#sharedPlaces == 0, "the comparison keeps the Hearthstone out of the shared place list")
	check(planCalls == 2, "a plan is made for each side of the comparison")
	-- Moved on while a comparison is still planning: an ask from well past it plans from where it stands.
	standX = 100
	check(ns.HearthSaving() == nil and #runs == 1, "moving on plans the comparison again")
	standX = 200
	check(ns.HearthSaving() == nil and #runs == 2 and runs[1].cancelled, "a farther ask replaces the one in flight")
	pump()
	standX = 0

	local plan = { legs = { { teleport = { bind = true, item = 6948 } } } }
	ns.JourneyPlan = function()
		return plan
	end
	local title, lines = ns.HearthPinTooltip("Goldshire", 85000)
	check(title == "Hearthstone", "the tooltip's title")
	check(lines[1] == "Goldshire", "the bind location comes first")
	check(lines[2] == "This journey uses it: 1:25 faster.", "the used state counts the time saved")
	check(lines[3] == "Click to save it.", "the used state says what a click does")
	plan = { legs = { { kind = "walk" } } }
	local _, unused = ns.HearthPinTooltip("Goldshire", 0)
	check(
		#unused == 2 and unused[2] == "Click to save it.",
		"a zero saving without a bind leg never claims the journey uses it"
	)
	local ignored, noTime = ns.HearthPinTooltip("Goldshire", nil)
	lines = noTime
	check(ignored == "Hearthstone", "the title is still there without a comparison")
	check(#lines == 2 and lines[2] == "Click to save it.", "no time line when no comparison could be made")

	local function texture()
		local t = {}
		function t.SetPoint() end
		function t:SetSize(width, height)
			self.width, self.height = width, height
		end
		function t:SetAlpha(alpha)
			self.alpha = alpha
		end
		function t.SetBlendMode() end
		return t
	end
	local function pin()
		local p = setmetatable({}, { __index = ns.HearthPinMixin })
		function p.CreateTexture()
			return texture()
		end
		function p:SetSize(width, height)
			self.width, self.height = width, height
		end
		function p:SetPosition(x, y)
			self.x, self.y = x, y
		end
		function p.UseFrameLevelType() end
		function p.SetIgnoreGlobalPinScale() end
		function p.SetScalingLimits() end
		p:OnLoad()
		return p
	end
	local button = pin()
	button:OnAcquired({ name = "Goldshire", map = 1, x = 10, y = 20 }, 0.4, 0.6)
	check(button.width == 22 and button.height == 22, "the button is 22 square")
	check(looked[1].kind == "innkeeper" and looked[1].size == 22, "the client's innkeeper atlas, never an item icon")
	check(looked[2].kind == "innkeeper", "its highlight wears the same art")
	check(button.x == 0.4 and button.y == 0.6, "it stands at the bind point")
end

print("hearth toggle: ok")
