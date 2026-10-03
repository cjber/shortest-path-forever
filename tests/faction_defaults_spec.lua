local function loadCore(saved)
	local frames = {}
	local env = setmetatable({
		ShortestPathForeverDB = saved,
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
	local ns = { Model = {} }
	local chunk = assert(loadfile("Core/Core.lua"))
	setfenv(chunk, env)("ShortestPathForever", ns)
	frames[1]:OnEvent("ADDON_LOADED", "ShortestPathForever")
	return ns
end
local fresh = loadCore(nil)
assert(fresh.db.otherFaction == false, "new installs avoid opposing-faction transport")
assert(fresh.db.hearthMinimumSavings == 0, "new installs preserve the fastest Hearthstone routing")
assert(loadCore({}).db.hearthMinimumSavings == 0, "old saves acquire the numeric default")
assert(
	loadCore({ hearthMinimumSavings = 300 }).db.hearthMinimumSavings == 300,
	"saved savings threshold survives reload"
)
assert(not fresh.RouteShown({ faction = "Horde" }), "hostile route hidden by default")
assert(fresh.RouteShown({ faction = "Alliance" }), "own faction route remains available")
assert(fresh.RouteShown({}), "neutral transport remains available")
local optedIn = loadCore({ otherFaction = true })
assert(optedIn.db.otherFaction == true, "saved opt-in survives reload")
assert(optedIn.RouteShown({ faction = "Horde" }), "saved opt-in allows opposing transport")
assert(loadCore({ otherFaction = false }).db.otherFaction == false, "saved opt-out survives reload")
print("faction_defaults_spec: defaults and saved preferences passed")
