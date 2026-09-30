local function loadCore(saved)
	local frames = {}
	local env = setmetatable({
		ShortestPathForeverDB = saved,
		GetRealmName = function()
			return "Test realm"
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
	local ns = { Model = { MAX_AGE = 86400 } }
	local chunk = assert(loadfile("Core.lua"))
	setfenv(chunk, env)("ShortestPathForever", ns)
	frames[1]:OnEvent("ADDON_LOADED", "ShortestPathForever")
	return ns
end
local fresh = loadCore(nil)
assert(fresh.db.otherFaction == false, "new installs avoid opposing-faction transport")
assert(not fresh.RouteShown({ faction = "Horde" }), "hostile route hidden by default")
assert(fresh.RouteShown({ faction = "Alliance" }), "own faction route remains available")
assert(fresh.RouteShown({}), "neutral transport remains available")
local optedIn = loadCore({ otherFaction = true })
assert(optedIn.db.otherFaction == true, "saved opt-in survives reload")
assert(optedIn.RouteShown({ faction = "Horde" }), "saved opt-in allows opposing transport")
assert(loadCore({ otherFaction = false }).db.otherFaction == false, "saved opt-out survives reload")
print("faction_defaults_spec: defaults and saved preferences passed")
