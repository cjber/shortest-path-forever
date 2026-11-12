-- Under the game's gamepad interface the addon leaves opening and turning the world map to the game (#158):
-- Forever's FrameControlsManager takes each into its focus in the same call, and the gamepad action bar calls the
-- protected SetPreferredGamepadInteractTarget from there. With mouse and keyboard nothing changes. Menus are
-- ForeverCore's own frames and stay safe, so they no longer change under the gamepad interface.
local style, opened, printed, mapShown, mapID, combat = 0, {}, {}, false, 1429, false
-- The client's own opener is restricted: ForeverCore.OpenMap runs it through securecallfunction, and the stub
-- records whether the call came that way.
local viaDelegate = false
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
	print = function(text)
		printed[#printed + 1] = text
	end,
}, { __index = _G })
local ForeverCore = dofile("tests/forever_core.lua")
ForeverCore.load(env, "ForeverCore")
local ns = {
	Model = {},
	L = setmetatable({}, {
		__index = function(_, phrase)
			return phrase
		end,
	}),
}
for _, file in ipairs({ "Locales/enUS.lua", "Core/Core.lua" }) do
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
print("gamepad_spec: the world map is left to the game under the gamepad interface: ok")
