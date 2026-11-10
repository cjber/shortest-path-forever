---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Our entries in the game's own menus (the world map's filter menu, the minimap's tracking menu) are added through
-- Menu.ModifyMenu, and the game runs each modifier every time it builds the menu: when the map opens and when the
-- menu opens. Each of ours runs behind two guards: it only ever gets a menu description (a table) to add to, and an
-- error in it is reported through ns.core.SafeCall instead of unwinding through Blizzard_Menu (#161).

-- `/path menutest map|nearby|both|off` leaves our world map filter menu entries out from the next /reload: an A/B
-- check for #161 that needs no file edits. "map" is the map filters, "nearby" the Nearby services submenu. It is
-- kept in ns.db.menuTest outside DEFAULTS, which holds only the settings page's options: a missing key reads as off.
local SKIPS = {
	map = { map = true },
	nearby = { nearby = true },
	both = { map = true, nearby = true },
}

---@class SPFMenuModifier
---@field tag string the menu's tag
---@field name string which of ours this is, for the A/B check and the error report
---@field build fun(owner: any, root: table, contextData: any)
---@field registered boolean whether the client holds this entry
---@field handle? any the client's registration, while it is in place

---@type SPFMenuModifier[]
local modifiers = {}

-- Puts each entry in place or takes it back out, as the gamepad interface comes and goes.
local function Sync()
	local gamepad = ns.GamepadUI()
	for _, modifier in ipairs(modifiers) do
		if gamepad and modifier.registered then
			local handle = modifier.handle
			if handle and type(handle.Unregister) == "function" then
				handle:Unregister()
				modifier.handle, modifier.registered = nil, false
			end
		elseif not gamepad and not modifier.registered then
			-- The client runs a new modifier once, right away, when it has already built that menu's description
			-- (Blizzard_Menu/Menu.lua's Menu.ModifyMenu). That run happens inside the addon's own code, so everything
			-- it touches is the addon's: the button's SignalUpdate writes the menu's state, and the gamepad focus the
			-- next open takes has its protected calls refused, blamed on this addon (#645). Descriptions are rebuilt
			-- before every open, and the client runs the modifiers of that build through its secure call
			-- (Menu.PopulateDescription), so ours waits for that build rather than building at registration.
			local registering = true
			modifier.handle = Menu.ModifyMenu(modifier.tag, function(owner, root, contextData)
				if registering or type(root) ~= "table" then
					return
				end
				ns.core.SafeCall(modifier.name .. " menu", modifier.build, owner, root, contextData)
			end)
			modifier.registered = true
			registering = false
		end
	end
end

-- Under the gamepad interface the client takes every menu it shows into the gamepad focus in the same call
-- (FrameControlsManager:FrameShown). A menu built with entries from an addon is tainted by that addon: the client
-- reads the entries while it builds the menu and writes the focus's own state as the addon's, so its next protected
-- call (SetPreferredGamepadInteractTarget) is refused and blamed on us (#645; cjber/skillup-forever#454 met the
-- same refusal in the professions filter). No addon entry can be built untainted, so the gamepad interface leaves
-- the game's menus to the game: our entries are withdrawn while it is on and put back when it is off.
ns.Init(function()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
	frame:SetScript("OnEvent", Sync)
	Sync()
end)

---@param tag string the menu's tag, e.g. "MENU_WORLD_MAP_TRACKING"
---@param name string which of ours this is, for the A/B check and the error report
---@param build fun(owner: any, root: table, contextData: any)
function ns.ModifyMenu(tag, name, build)
	local skip = tag == "MENU_WORLD_MAP_TRACKING" and SKIPS[ns.db.menuTest]
	if skip and skip[name] then
		return
	end
	modifiers[#modifiers + 1] = { tag = tag, name = name, build = build, registered = false }
	Sync()
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
