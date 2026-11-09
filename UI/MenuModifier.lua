---@class SPFNamespace
local ns = select(2, ...)

-- Our entries in the game's own menus (the world map's filter menu, the minimap's tracking menu) are added through
-- Menu.ModifyMenu, and the game runs each modifier every time it builds the menu: when the map opens and when the
-- menu opens. Each of ours runs behind two guards: it only ever gets a menu description (a table) to add to, and an
-- error in it is reported through ns.SafeCall instead of unwinding through Blizzard_Menu (#161).

-- `/path menutest map|nearby|both|off` leaves our world map filter menu entries out from the next /reload: an A/B
-- check for #161 that needs no file edits. "map" is the map filters, "nearby" the Nearby services submenu. It is
-- kept in ns.db.menuTest outside DEFAULTS, which holds only the settings page's options: a missing key reads as off.
local SKIPS = {
	map = { map = true },
	nearby = { nearby = true },
	both = { map = true, nearby = true },
}

-- The menu modifiers we have registered, with Menu.ModifyMenu's handle, so the gamepad interface can take ours out
-- while it owns the UI. A native menu runs its modifiers in the call that shows it, and the gamepad's
-- FrameControlsManager takes the shown menu into its focus in that same call. An addon modifier on that path leaves
-- its taint on the focus write, so the menu's close runs the gamepad action bar's protected
-- SetPreferredGamepadInteractTarget tainted, and the client blocks it (#158, #581). Under the gamepad interface the
-- game's own menus stay the game's, as the addon's own menus already do; the mouse and keyboard keep every entry.
local modifiers = {}

local function GamepadUI()
	return ns.GamepadUI and ns.GamepadUI() == true
end

local function Register(entry)
	if entry.handle or GamepadUI() then
		return
	end
	entry.handle = Menu.ModifyMenu(entry.tag, entry.build)
end

local function Unregister(entry)
	local handle = entry.handle
	entry.handle = nil
	if handle and handle.Unregister then
		handle:Unregister()
	end
end

local function ApplyInterface()
	for _, entry in ipairs(modifiers) do
		if GamepadUI() then
			Unregister(entry)
		else
			Register(entry)
		end
	end
end

local transition = CreateFrame("Frame")
if transition.RegisterEvent then
	transition:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
	transition:SetScript("OnEvent", ApplyInterface)
end

---@param tag string the menu's tag, e.g. "MENU_WORLD_MAP_TRACKING"
---@param name string which of ours this is, for the A/B check and the error report
---@param build fun(owner: any, root: table, contextData: any)
function ns.ModifyMenu(tag, name, build)
	local skip = tag == "MENU_WORLD_MAP_TRACKING" and SKIPS[ns.db.menuTest]
	if skip and skip[name] then
		return
	end
	local entry = {
		tag = tag,
		build = function(owner, root, contextData)
			if type(root) ~= "table" then
				return
			end
			ns.SafeCall(name .. " menu", build, owner, root, contextData)
		end,
	}
	modifiers[#modifiers + 1] = entry
	Register(entry)
end

-- The slash command's half: answers whether the value was one it knows.
---@param value string
---@return boolean
function ns.SetMenuTest(value)
	if value ~= "off" and not SKIPS[value] then
		return false
	end
	ns.db.menuTest = value ~= "off" and value or nil
	return true
end
