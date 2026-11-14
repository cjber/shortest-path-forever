-- The quick Use Hearthstone switch (#707): the saved flag keeps only the Hearthstone out of journeys, the tracker's
-- journey menu and the world map's innkeeper button flip it, a flip replans the journey, and the button's tooltip
-- reads both states.
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

	-- The map button still knows the Hearthstone while it is saved for later, so it can be turned back on.
	local hearth = assert(Hearthstone(5000))
	check(hearth.name == "Goldshire" and hearth.map == 0 and hearth.x == 10 and hearth.y == 20, "the bind point")
	check(hearth.place.item == 6948 and hearth.readyAt == 5000, "the Hearthstone's own place, ready now")
	runtime.db.useHearthstone = false
	check(Hearthstone(5000) ~= nil, "the saved button still knows where the Hearthstone goes")
	runtime.db.teleports = false
	check(Hearthstone(5000) == nil, "with every teleport off, the button has nothing to offer")
	runtime.db.teleports = true
	items[6948] = 0
	check(Hearthstone(5000) == nil, "without the Hearthstone, no button")
	items[6948] = 1
	itemCooldowns[6948] = { 50, 3600, true }
	check(assert(Hearthstone(5000)).readyAt == 5000 + 3550000, "the Hearthstone's cooldown is its readiness")
	tick()
	check(registered.HEARTHSTONE_BOUND and registered.PLAYER_ENTERING_WORLD, "the bind events are watched")
end

-- The journey: a flip replans, the hearth leg leaves, and the class teleport still carries the journey.
do
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local ns = driver.ns
	local hearth = { map = 1, x = 6930, y = 0, spell = 8690, item = 6948, cast = 10000 }
	local class = { map = 1, x = 3500, y = 0, spell = 3561, cast = 10000 }
	ns.teleports, ns.teleportReady = { class, hearth }, { 0, 0 }
	-- What Transport/Teleports.lua returns: the Hearthstone only while the switch allows it.
	ns.UsableTeleports = function()
		local places, ready = {}, {}
		for index, teleport in ipairs(ns.teleports) do
			if teleport.item ~= 6948 or ns.db.useHearthstone ~= false then
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
end

-- The map button's tooltip and its two looks, without a client frame.
do
	local answers = { enabled = true }
	local looked = {}
	local sharedPlaces, planCalls = {}, 0
	local ns = {
		L = setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		}),
		Canvas = { PinMixin = {} },
		Init = function() end,
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
			return { map = 1, x = 100, y = 100 }
		end,
		JourneyPosition = function()
			return 0, 0, nil, 1
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
				place = { map = 1, x = 10, y = 20, item = 6948, spell = 8690, cast = 10000 },
				readyAt = 1000,
			}
		end,
		PlanContext = {
			Options = function()
				return { now = 1000, teleports = sharedPlaces, teleportReady = {} }
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
		CreateFromMixins = function(mixin)
			return setmetatable({}, { __index = mixin })
		end,
		InCombatLockdown = function()
			return false
		end,
	}, { __index = _G })
	setfenv(assert(loadfile("UI/HearthPin.lua")), env)("ShortestPathForever", ns)

	-- The comparison plans the same journey with and without the Hearthstone, without leaking it into the planner's
	-- shared place list (which Transport/Teleports.lua keeps between calls).
	check(ns.HearthSaving() == 5000, "the comparison measures the journey with and without the Hearthstone")
	check(#sharedPlaces == 0, "the comparison keeps the Hearthstone out of the shared place list")
	check(planCalls == 2, "a plan is made for each side of the comparison")

	local title, lines = ns.HearthPinTooltip("Goldshire", 85000, true)
	check(title == "Hearthstone", "the tooltip's title")
	check(lines[1] == "Goldshire", "the bind location comes first")
	check(lines[2] == "This journey uses it: 1:25 faster.", "the used state counts the time saved")
	check(lines[3] == "Click to save it.", "the used state says what a click does")
	title, lines = ns.HearthPinTooltip("Goldshire", nil, false)
	check(title == "Hearthstone" and lines[1] == "Goldshire", "the saved state still names the bind point")
	check(lines[2] == "Saved for later.", "the saved state says it waits")
	check(lines[3] == "Click to use it.", "the saved state says what a click does")
	local ignored, noTime = ns.HearthPinTooltip("Goldshire", nil, true)
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
		function t:SetDesaturated(value)
			self.desaturated = value
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
	check(button.Texture.alpha == 1 and not button.Texture.desaturated, "the used state is full strength and coloured")
	answers.enabled = false
	local saved = pin()
	saved:OnAcquired({ name = "Goldshire", map = 1, x = 10, y = 20 }, 0.4, 0.6)
	check(saved.Texture.alpha == 0.75 and saved.Texture.desaturated, "a saved Hearthstone is faded and greyed")
	answers.enabled = true
end

print("hearth toggle: ok")
