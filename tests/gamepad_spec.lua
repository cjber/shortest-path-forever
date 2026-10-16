-- Under the game's gamepad interface the addon leaves opening the world map to the game (#158): Forever's gamepad
-- layer counts a window as belonging to whatever code opened it, and the gamepad action bar later calls the protected
-- SetPreferredGamepadInteractTarget from that path. With mouse and keyboard nothing changes.
local style, opened, printed, mapShown = 0, {}, {}, false
local env = setmetatable({
	ShortestPathForeverDB = {},
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
	},
	WorldMapFrame = {
		IsShown = function()
			return mapShown
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
for _, file in ipairs({ "Core/SafeCall.lua", "Core/Core.lua" }) do
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end

assert(not ns.GamepadUI(), "mouse and keyboard is not the gamepad interface")
assert(ns.OpenWorldMap(1429) and opened[1] == 1429 and #printed == 0, "the map opens as before")
style = 1
assert(ns.GamepadUI(), "the gamepad interface is seen")
assert(not ns.OpenWorldMap(1429) and #opened == 1, "under it the addon does not open the map")
assert(#printed == 1 and printed[1]:find("Open the world map to see it.", 1, true), "it says to open the map")
assert(not ns.OpenWorldMap(nil, "Use its menu.") and printed[2]:find("Use its menu.", 1, true), "a caller's hint")
mapShown = true
assert(ns.OpenWorldMap(1446) and opened[2] == 1446, "a map the game opened is turned to the place by the game")
assert(#printed == 2, "with the map already open it says nothing")
env.C_InputInterfaceStyle = nil
assert(not ns.GamepadUI(), "a client without the interface style API is mouse and keyboard")
print("gamepad_spec: the world map is left to the game under the gamepad interface: ok")
