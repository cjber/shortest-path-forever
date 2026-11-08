-- Under the game's gamepad interface the addon leaves opening and turning the world map, and opening menus, to the
-- game (#158): Forever's FrameControlsManager takes each into its focus in the same call, and the gamepad action bar
-- calls the protected SetPreferredGamepadInteractTarget from there. With mouse and keyboard nothing changes.
local style, opened, printed, mapShown, mapID, menus, combat = 0, {}, {}, false, 1429, {}, false
local env = setmetatable({
	ShortestPathForeverDB = {},
	GetServerTime = function()
		return 100
	end,
	InCombatLockdown = function()
		return combat
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
			opened[#opened + 1] = uiMap or "here"
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
	MenuUtil = {
		CreateContextMenu = function(owner)
			menus[#menus + 1] = owner
			return owner
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
local ns = {
	Model = {},
	L = setmetatable({}, {
		__index = function(_, phrase)
			return phrase
		end,
	}),
}
for _, file in ipairs({ "Core/SafeCall.lua", "Core/Log.lua", "Core/Core.lua" }) do
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end

assert(not ns.GamepadUI(), "mouse and keyboard is not the gamepad interface")
assert(ns.OpenWorldMap(1429) and opened[1] == 1429 and #printed == 0, "the map opens as before")
assert(ns.ContextMenu("pin", print) == "pin" and menus[1] == "pin", "menus open as before")
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
assert(ns.ContextMenu("pin", print) == nil and #menus == 1, "under it the addon opens no menu")
assert(printed[5]:find("This menu needs mouse and keyboard.", 1, true), "it says why")
env.C_InputInterfaceStyle = nil
assert(not ns.GamepadUI(), "a client without the interface style API is mouse and keyboard")
print("gamepad_spec: the world map and menus are left to the game under the gamepad interface: ok")
