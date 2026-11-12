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
assert(fresh.db.otherFaction == false, "new installs avoid opposing-faction transport")
assert(fresh.db.hearthMinimumSavings == 0, "new installs preserve the fastest Hearthstone routing")
assert(loadCore({}).db.hearthMinimumSavings == 0, "old saves acquire the numeric default")
assert(
	loadCore({ hearthMinimumSavings = 300 }).db.hearthMinimumSavings == 300,
	"saved savings threshold survives reload"
)
assert(fresh.db.hearth == true and fresh.db.teleports == true, "new installs use the Hearthstone and class teleports")
assert(loadCore({ teleports = false }).db.hearth == false, "an old opt-out keeps the Hearthstone off")
assert(loadCore({ teleports = true }).db.hearth == true, "an old opt-in keeps the Hearthstone on")
assert(loadCore({ teleports = false, hearth = true }).db.hearth == true, "a saved Hearthstone choice wins")
assert(fresh.db.teleportMinimumSavings == 0, "class teleports have no minimum saving by default")
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
