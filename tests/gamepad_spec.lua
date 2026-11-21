-- Under the game's gamepad interface the addon leaves opening and turning the world map to the game (#158):
-- Forever's FrameControlsManager takes each into its focus in the same call, and the gamepad action bar calls the
-- protected SetPreferredGamepadInteractTarget from there. With mouse and keyboard nothing changes. Menus are
-- ForeverCore's own frames and stay safe, so they no longer change under the gamepad interface.
local style, opened, printed, mapShown, mapID, combat = 0, {}, {}, false, 1429, false
-- The client's own opener is restricted: ForeverCore.OpenMap runs it through securecallfunction, and the stub
-- records whether the call came that way.
local viaDelegate = false
local chat = {}
local env = setmetatable({
	ShortestPathForeverDB = {},
	SlashCmdList = {},
	GetServerTime = function()
		return 100
	end,
	InCombatLockdown = function()
		return combat
	end,
	securecallfunction = function(fn, ...)
		viaDelegate = true
		local result = fn(...)
		viaDelegate = false
		return result
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
		return frame
	end,
	Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } },
	C_InputInterfaceStyle = {
		GetCurrentStyle = function()
			return style
		end,
	},
	C_Map = {
		OpenWorldMap = function(uiMap)
			opened[#opened + 1] = { uiMap = uiMap or "here", secure = viaDelegate }
		end,
		GetMapInfo = function(uiMap)
			return uiMap == 1415 and { name = "Eastern Kingdoms" } or nil
		end,
	},
	WorldMapFrame = {
		IsShown = function()
			return mapShown
		end,
		GetMapID = function()
			return mapID
		end,
	},
	NORMAL_FONT_COLOR = {
		WrapTextInColorCode = function(_, text)
			return text
		end,
	},
	DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, message)
			chat[#chat + 1] = message
		end,
	},
	print = function(text)
		printed[#printed + 1] = text
	end,
}, { __index = _G })
local ForeverCore = dofile("tests/forever_core.lua")
ForeverCore.load(env, "ForeverCore")
local corpseActive = true
local ns = {
	Model = {},
	JourneyGuide = { RefreshTracker = function() end },
	JourneySearch = { Clear = function() end },
	Corpse = {
		Active = function()
			return corpseActive
		end,
		Point = function()
			return { uiMap = 1415 }
		end,
	},
	L = setmetatable({}, {
		__index = function(_, phrase)
			return phrase
		end,
	}),
}
for _, file in ipairs({ "Locales/enUS.lua", "Core/Core.lua", "Journey/Journey.lua" }) do
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end

assert(not ns.GamepadUI(), "mouse and keyboard is not the gamepad interface")
assert(ns.OpenWorldMap(1429) and opened[1].uiMap == 1429 and #printed == 0, "the map opens as before")
assert(opened[1].secure, "the map opens through ForeverCore's secure opener, not the restricted call (#333)")
combat = true
assert(not ns.OpenWorldMap(1429) and #opened == 1, "in combat the addon does not open the map (#444)")
assert(#printed == 1 and printed[1]:find("Open the world map to see it.", 1, true), "it says to open the map")
combat = false
printed = {}
style = 1
assert(ns.GamepadUI(), "the gamepad interface is seen")
assert(not ns.OpenWorldMap(1429) and #opened == 1, "under it the addon does not open the map")
assert(#printed == 1 and printed[1]:find("Open the world map to see it.", 1, true), "it says to open the map")
assert(not ns.OpenWorldMap(nil, "Use its menu.") and printed[2]:find("Use its menu.", 1, true), "a caller's hint")
mapShown = true
assert(ns.OpenWorldMap(1429) and ns.OpenWorldMap() and #opened == 1, "a map the player has on the place is used as is")
assert(#printed == 2, "with the map already on the place it says nothing")
assert(not ns.OpenWorldMap(1415) and #opened == 1, "the addon never turns the map itself")
assert(printed[3]:find("Turn the world map to Eastern Kingdoms to see it.", 1, true), "it says where to turn it")
assert(not ns.OpenWorldMap(1446) and printed[4]:find("Open the world map", 1, true), "an unnamed map: the hint")
env.C_InputInterfaceStyle = nil
assert(not ns.GamepadUI(), "a client without the interface style API is mouse and keyboard")
ns.Locate = function(point)
	return point
end
ns.InstanceEntrance = function(point)
	return point
end

local function open(where)
	return env.ForeverCore.Open("ShortestPathForever", where)
end
local directMessages, mapOpens = #printed, #opened
assert(ns.StartJourney({ uiMap = 1429 }), "queue a journey behind the corpse run")
assert(open(1429) == true and opened[mapOpens + 1].uiMap == 1429)
assert(open("journey") == true and opened[mapOpens + 2].uiMap == 1415, "a corpse run opens the corpse point")
corpseActive = false
assert(open("journey") == true and opened[mapOpens + 3].uiMap == 1429, "the journey opens its goal after recovery")
assert(open() == true and opened[mapOpens + 4].uiMap == "here")
for _, where in ipairs({ "invalid", {}, 0, -1, 1.5, math.huge, 0 / 0 }) do
	assert(open(where) == false, "invalid targets are refused")
end
assert(#opened == mapOpens + 4 and #chat == 0)
corpseActive = true
env.C_InputInterfaceStyle = {
	GetCurrentStyle = function()
		return 1
	end,
}
assert(open(1429) == true and #opened == mapOpens + 4 and #chat == 0)
local accepted, reason = open("journey")
assert(accepted == false and reason == "Turn the world map to Eastern Kingdoms to see it.")
assert(#chat == 1 and chat[1] == reason and #printed == directMessages and #opened == mapOpens + 4)
combat = true
accepted, reason = open(1429)
assert(accepted == false and reason == "Unavailable in combat", "Core refuses combat even with the requested map up")
assert(#chat == 2 and chat[2] == reason and #printed == directMessages and #opened == mapOpens + 4)
print("gamepad_spec: direct and registered map openers passed")
