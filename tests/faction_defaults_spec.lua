local ForeverCore = dofile("tests/forever_core.lua")

local function loadCore(saved)
	local frames = {}
	local env = setmetatable({
		ShortestPathForeverDB = saved,
		SlashCmdList = {},
		C_Timer = {
			NewTicker = function()
				return { Cancel = function() end }
			end,
		},
		IsPlayerMoving = function()
			return false
		end,
		GetServerTime = function()
			return 100
		end,
		UnitFactionGroup = function()
			return "Alliance"
		end,
		geterrorhandler = function()
			return function(err)
				error(err)
			end
		end,
		CreateFrame = function()
			local frame = {}
			function frame.RegisterEvent() end
			function frame.RegisterUnitEvent() end
			function frame.UnregisterEvent() end
			function frame:SetScript(name, fn)
				self[name] = fn
			end
			frames[#frames + 1] = frame
			return frame
		end,
	}, { __index = _G })
	ForeverCore.load(env, "ForeverCore")
	local function fire(event, name)
		for _, frame in ipairs(frames) do
			if frame.OnEvent then
				frame:OnEvent(event, name)
			end
		end
	end
	fire("ADDON_LOADED", "ForeverCore")
	local ns = { Model = {} }
	for _, file in ipairs({ "Locales/enUS.lua", "Core/Core.lua" }) do
		setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
	end
	fire("ADDON_LOADED", "ShortestPathForever")
	return ns
end

local fresh = loadCore(nil)
assert(fresh.db.restedxp == true, "new installs follow RestedXP when available")
assert(loadCore({}).db.restedxp == true, "saves without a RestedXP preference acquire the default")
assert(loadCore({ restedxp = false }).db.restedxp == false, "saved RestedXP opt-out survives reload")
assert(fresh.db.guidelime == true, "new installs follow Guidelime when available")
assert(loadCore({}).db.guidelime == true, "saves without a Guidelime preference acquire the default")
assert(loadCore({ guidelime = false }).db.guidelime == false, "saved Guidelime opt-out survives reload")
assert(fresh.db.dugi == false, "new installs leave Dugi opt-in")
assert(loadCore({}).db.dugi == false, "saves without a Dugi preference keep it off")
assert(loadCore({ dugi = true }).db.dugi == true, "saved Dugi opt-in survives reload")
assert(fresh.db.otherFaction == false, "new installs avoid opposing-faction transport")
assert(fresh.db.hearthMinimumSavings == 0, "new installs preserve the fastest Hearthstone routing")
assert(fresh.db.followRoads == true, "new installs follow roads")
assert(fresh.db.roadDetour == 50, "and keep the 50% road allowance")
assert(loadCore({}).db.hearthMinimumSavings == 0, "old saves acquire the numeric default")
assert(
	loadCore({ hearthMinimumSavings = 300 }).db.hearthMinimumSavings == 300,
	"saved savings threshold survives reload"
)
assert(fresh.db.useHearthstone == true and fresh.db.teleports == true, "new installs plan every teleport")
assert(
	loadCore({ teleports = false }).db.useHearthstone == false,
	"an old save that turned off 'Use hearth and teleports' keeps the Hearthstone off"
)
assert(loadCore({ teleports = true }).db.useHearthstone == true, "an old save that kept it on keeps the Hearthstone on")
local migrated = loadCore({ teleports = false, useHearthstone = true })
assert(
	migrated.db.useHearthstone == false,
	"the split moves an old combined switch off once, whatever was defaulted since"
)
migrated.db.useHearthstone = true
assert(loadCore(migrated.db).db.useHearthstone == true, "turning the Hearthstone back on afterwards keeps it on")
assert(
	loadCore({ teleports = true, useHearthstone = true }).db.useHearthstone == true,
	"a save with both switches on is unchanged"
)
assert(loadCore({ useHearthstone = false }).db.teleports == true, "class teleports keep their own default")
assert(fresh.db.teleportMinimumSavings == 0, "class teleports need no saving by default")
assert(loadCore({}).db.teleportMinimumSavings == 0, "old saves acquire the class teleport default")
assert(
	loadCore({ teleportMinimumSavings = 120 }).db.teleportMinimumSavings == 120,
	"saved class teleport threshold survives reload"
)
assert(not fresh.RouteShown({ faction = "Horde" }), "hostile route hidden by default")
assert(fresh.RouteShown({ faction = "Alliance" }), "own faction route remains available")
assert(fresh.RouteShown({}), "neutral transport remains available")
local optedIn = loadCore({ otherFaction = true })
assert(optedIn.db.otherFaction == true, "saved opt-in survives reload")
assert(optedIn.RouteShown({ faction = "Horde" }), "saved opt-in allows opposing transport")
assert(loadCore({ otherFaction = false }).db.otherFaction == false, "saved opt-out survives reload")
assert(fresh.db.stats == true and fresh.db.statsShare == nil, "new profiles record local stats only")
for _, saved in ipairs({
	{ stats = false },
}) do
	local recording = saved.stats
	local loaded = loadCore(saved)
	if recording ~= nil then
		assert(loaded.db.stats == recording, "saved recording choice survives")
	end
	local reloaded = loadCore(loaded.db)
	assert(reloaded.db.stats == loaded.db.stats, "reload retains choices")
end
print("faction_defaults_spec: defaults and saved preferences passed")
