-- Run from the repository root: luajit tests/smoke_spec.lua
-- The whole interactive surface, headless: every saved setting driven through its own value-changed callback and
-- through ns.SetOption, the minimap route button, the compass, the tracker's headers and context menus, the world
-- map's pins and their Ends menu, the planning paths, and the settings index with its subpages, across
-- representative profiles. Every action asserts no Lua error was added, and a crash is reported as
-- "<profile> <screen/frame/setting> <verb>: <error>", attributable to the setting, frame or screen that raised it.
-- What it cannot reach is the live client a /reload runs against: the native tracker host and the flight map's
-- real buttons are checked by tracker_host_spec.lua and taxi_spec.lua.
local dir = arg[0]:match("^(.*)/") or "tests"

-- The map pins and the Spinner run against checksum-pinned Blizzard source, which tests/ui.sh fetches. A spec run
-- on a fresh checkout fetches it here so both "luajit tests/*_spec.lua" and tests/ui.sh see the same client.
local probe = "tools/.cache/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/Spinner.lua"
do
	local handle = io.open(probe)
	if handle then
		handle:close()
	else
		local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
		assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture for tests/smoke_spec.lua")
	end
end

local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [==[
--[[ The run's own harness: an action's added errors or its throw become one failure naming it. ]]
local checks, failures = 0, {}
local stats = {
	profiles = 0,
	frames = 0,
	clicks = 0,
	hovers = 0,
	menus = 0,
	pins = 0,
	settings = 0,
	rows = 0,
	buttons = 0,
	paths = 0,
	compass = 0,
	routeButton = 0,
}

local function SortedKeys(t)
	local keys = {}
	for key in pairs(t) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function Run(label, fn)
	checks = checks + 1
	local before = #errors
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		failures[#failures + 1] = label .. ": driver threw:\n" .. tostring(err)
		return
	end
	if #errors > before then
		local raised = {}
		for index = before + 1, #errors do
			raised[#raised + 1] = errors[index]
		end
		failures[#failures + 1] = label .. ": " .. table.concat(raised, "\n---\n")
	end
end

-- The client runs timer and frame callbacks; flush them so a setting's re-render and the compass poll really run.
local function Advance(seconds)
	for _ = 1, math.max(1, math.floor((seconds or 0.05) * 60)) do
		T = T + 1 / 60
		for _, ticker in ipairs(tickers) do
			if not ticker.cancelled and T >= ticker.next then
				ticker.next = T + ticker.every
				ticker.fn()
			end
		end
		for index = #pending, 1, -1 do
			if T >= pending[index].at then
				local timer = table.remove(pending, index)
				timer.fn()
			end
		end
		for _, frame in ipairs(frames) do
			if frame:IsShown() and frame.scripts.OnUpdate then
				frame.scripts.OnUpdate(frame, 1 / 60)
			end
		end
	end
end

local function Flush()
	Advance(0.05)
end

local function Name(frame)
	local name = frame.name
	if not name then
		name = frame.text
	end
	if not name then
		local parent = frame.parent
		name = (frame.objectType or "Frame") .. "@" .. tostring(parent and (parent.name or parent.objectType) or "?")
	end
	return name
end

local function Owned(frame)
	local node = frame
	while node do
		local name = node.name
		if name and name:match("^ShortestPathForever") then
			return true
		end
		node = node.parent
	end
	return false
end

local function Interactive(frame)
	local scripts = frame.scripts
	return (scripts and (scripts.OnClick or scripts.OnMouseUp or scripts.OnMouseDown)) or frame.mouseUpHandler ~= nil
end

local function Hoverable(frame)
	local scripts = frame.scripts
	return (scripts and (scripts.OnEnter or scripts.OnLeave)) or frame.OnMouseEnter ~= nil
end

local function ClickFrame(frame, button)
	local scripts = frame.scripts or {}
	if scripts.OnClick then
		scripts.OnClick(frame, button)
	end
	if scripts.OnMouseUp then
		scripts.OnMouseUp(frame, button)
	end
	if frame.mouseUpHandler then
		frame.mouseUpHandler(frame, button, true)
	end
	if scripts.OnMouseDown then
		scripts.OnMouseDown(frame, button)
	end
end

local function HoverFrame(frame, enter)
	local scripts = frame.scripts or {}
	if enter then
		if frame.OnMouseEnter then
			frame.OnMouseEnter(frame)
		elseif scripts.OnEnter then
			scripts.OnEnter(frame)
		end
		frame.mouseOver = true
	else
		if frame.OnMouseLeave then
			frame.OnMouseLeave(frame)
		elseif scripts.OnLeave then
			scripts.OnLeave(frame)
		end
		frame.mouseOver = false
	end
end

--[[ The fixture's own recording root for MenuUtil/Menu.ModifyMenu entries. ]]
local function MenuRoot()
	local entries = {}
	local function entry(text)
		local record = { text = text }
		entries[#entries + 1] = record
		return record
	end
	local root = {}
	function root:CreateCheckbox(text, get, set)
		local record = entry(text)
		record.get, record.click = get, set
		return {
			AddInitializer = function(_, fn)
				record.initializer = fn
			end,
		}
	end
	function root:CreateButton(text, click)
		local record = entry(text)
		record.click = click
		return { SetEnabled = noop }
	end
	function root:CreateRadio(text, get, set)
		local record = entry(text)
		record.get, record.click = get, set
	end
	function root:CreateDivider() end
	function root:CreateTitle(text)
		entry(text)
	end
	return root, entries
end

local function DrainContext(label)
	local menu = context
	context = {}
	for _, key in ipairs(SortedKeys(menu)) do
		local item = menu[key]
		stats.menus = stats.menus + 1
		if item.get then
			Run(label .. " context " .. key .. " get", function()
				item.get()
			end)
		end
		if item.click then
			Run(label .. " context " .. key, function()
				item.click()
				Flush()
			end)
		end
	end
end

local function DriveEntries(label, entries)
	for _, record in ipairs(entries) do
		stats.menus = stats.menus + 1
		if record.get then
			Run(label .. " menu " .. record.text .. " get", function()
				record.get()
			end)
		end
		if record.click then
			Run(label .. " menu " .. record.text, function()
				record.click()
				Flush()
			end)
		end
		if record.initializer then
			Run(label .. " menu " .. record.text .. " initializer", function()
				record.initializer({
					AttachTexture = function()
						return { SetSize = noop, SetPoint = noop, SetAtlas = noop }
					end,
					fontString = { SetPoint = noop, GetUnboundedStringWidth = function()
						return 50
					end },
				})
			end)
		end
		-- A click can open another menu (a hub pin's Ends list); drain what it recorded.
		if next(context) ~= nil then
			DrainContext(label .. " nested")
		end
	end
end

local function DriveFrames(label)
	local list = {}
	for _, frame in ipairs(frames) do
		if frame:IsVisible() and (Interactive(frame) or Hoverable(frame)) and Owned(frame) then
			list[#list + 1] = frame
		end
	end
	for _, frame in ipairs(list) do
		if frame:IsVisible() then
			local tag = label .. " frame " .. Name(frame)
			stats.frames = stats.frames + 1
			if Hoverable(frame) then
				stats.hovers = stats.hovers + 2
				Run(tag .. " enter", function()
					HoverFrame(frame, true)
				end)
				Run(tag .. " leave", function()
					HoverFrame(frame, false)
				end)
			end
			if Interactive(frame) then
				for _, button in ipairs({ "LeftButton", "RightButton" }) do
					stats.clicks = stats.clicks + 1
					Run(tag .. " click " .. button, function()
						context = {}
						ClickFrame(frame, button)
						DrainContext(tag)
						Flush()
					end)
				end
				for _, modifier in ipairs({ "shift", "ctrl" }) do
					stats.clicks = stats.clicks + 1
					Run(tag .. " " .. modifier .. "-click", function()
						local wasShift, wasModifier = shiftDown, modifierDown
						shiftDown, modifierDown = modifier == "shift", modifier == "ctrl"
						context = {}
						ClickFrame(frame, "LeftButton")
						shiftDown, modifierDown = wasShift, wasModifier
						DrainContext(tag)
						Flush()
					end)
				end
			end
		end
	end
end

local function DrivePins(label)
	for _, template in ipairs(SortedKeys(active)) do
		-- Only the addon's own pins; the native WaypointLocationPinTemplate belongs to Blizzard's provider.
		if template:match("^ShortestPathForever") then
			local snapshot = {}
			for index, pin in ipairs(active[template] or {}) do
				if pin:IsShown() then
					snapshot[#snapshot + 1] = pin
				end
			end
			for index, pin in ipairs(snapshot) do
				stats.pins = stats.pins + 1
				local tag = ("%s pin %s#%d"):format(label, template, index)
				if pin.OnMouseEnter then
					Run(tag .. " enter", function()
						pin:OnMouseEnter()
					end)
				end
				if pin.OnMouseLeave then
					Run(tag .. " leave", function()
						pin:OnMouseLeave()
					end)
				end
				if pin.RefreshTooltip then
					Run(tag .. " tooltip", function()
						pin:RefreshTooltip()
					end)
				end
				if pin.OnClick then
					for _, button in ipairs({ "LeftButton", "RightButton" }) do
						Run(tag .. " click " .. button, function()
							context = {}
							pin:OnClick(button)
							DrainContext(tag)
							Flush()
						end)
					end
					Run(tag .. " modifier-click", function()
						local was = modifierDown
						modifierDown = true
						context = {}
						pin:OnClick("LeftButton")
						modifierDown = was
						DrainContext(tag)
					end)
				end
			end
		end
	end
end

local function DriveSettings(label)
	-- Every key, both values, through the public setter (the map's filter menu uses it too).
	for _, key in ipairs(SortedKeys(ns.Defaults)) do
		for _, value in ipairs({ true, false }) do
			stats.settings = stats.settings + 1
			Run(("%s setting %s=%s"):format(label, key, tostring(value)), function()
				ns.SetOption(key, value)
				Flush()
			end)
		end
	end
	-- The real settings row callback, as the checkbox fires it: the saved value, then the addon's onChanged.
	for _, setting in ipairs(addonSettings) do
		for _, value in ipairs({ true, false }) do
			stats.rows = stats.rows + 1
			Run(("%s settings row %s=%s"):format(label, setting.key, tostring(value)), function()
				ns.db[setting.key] = value
				if setting.cb then
					setting.cb()
				end
				Flush()
			end)
		end
	end
end

local function DriveSettingsPages(label)
	for _, button in ipairs(settingsButtons) do
		stats.buttons = stats.buttons + 1
		Run(("%s settings index %s"):format(label, button.initializer.name), function()
			local before = #openedCategories
			button.initializer.callback()
			assert(#openedCategories > before, "an index button opens its page")
			Flush()
		end)
	end
	for _, row in ipairs(settingsRows) do
		local setting = assert(row.initializer and row.initializer.setting, "a settings row is a checkbox")
		stats.rows = stats.rows + 1
		Run(("%s settings page %s"):format(label, setting.key), function()
			setting:SetValue(not ns.db[setting.key])
			Flush()
		end)
	end
end

local function DriveMenus(label)
	context = {}
	if menus.MENU_WORLD_MAP_TRACKING then
		local root, entries = MenuRoot()
		Run(label .. " world map filter menu", function()
			menus.MENU_WORLD_MAP_TRACKING(nil, root)
		end)
		DriveEntries(label .. " world map filter", entries)
	end
	if menus.MENU_MINIMAP_TRACKING then
		local root, entries = MenuRoot()
		Run(label .. " minimap tracking menu", function()
			menus.MENU_MINIMAP_TRACKING(nil, root)
		end)
		DriveEntries(label .. " minimap tracking", entries)
	end
	if menus.MENU_QUEST_MAP_LOG_TITLE then
		local root, entries = MenuRoot()
		Run(label .. " quest map log menu", function()
			menus.MENU_QUEST_MAP_LOG_TITLE({ questID = 843 }, root)
		end)
		DriveEntries(label .. " quest map log", entries)
	end
	if menus.MENU_QUEST_OBJECTIVE_TRACKER then
		local tracker = ShortestPathForeverObjectiveTracker
		local block = { HeaderButton = {}, parentModule = tracker }
		block.HeaderButton.GetParent = function()
			return block
		end
		local saved = tracker.GetContextMenuParent
		tracker.GetContextMenuParent = function()
			return "owner"
		end
		mouseFoci = { block.HeaderButton }
		local root, entries = MenuRoot()
		Run(label .. " objective tracker menu", function()
			menus.MENU_QUEST_OBJECTIVE_TRACKER("owner", root)
		end)
		mouseFoci = {}
		tracker.GetContextMenuParent = saved
		DriveEntries(label .. " objective tracker", entries)
	end
	-- The tracker's own block headers: left toggles Guide, right opens the journey menu.
	local tracker = ShortestPathForeverObjectiveTracker
	if tracker then
		for _, entry in ipairs(tracker.blocks) do
			local block = tracker:GetExistingBlock(entry.key)
			if block then
				for _, button in ipairs({ "LeftButton", "RightButton" }) do
					Run(("%s tracker header %s %s"):format(label, tostring(entry.key), button), function()
						context = {}
						tracker:OnBlockHeaderClick(block, button)
						DrainContext(label)
						Flush()
					end)
				end
			end
		end
	end
end

-- A dock pin hovered while a filter changes; this exercises a possible setting-click error path.
local function DriveHoveredSetting(label)
	Run(label .. " refresh map", function()
		ns.RefreshMap()
		Flush()
	end)
	local hovered
	for _, template in ipairs({ "ShortestPathForeverDockPinTemplate", "ShortestPathForeverPortalPinTemplate" }) do
		for _, pin in ipairs(active[template] or {}) do
			if pin:IsShown() and pin.OnMouseEnter then
				hovered = pin
				break
			end
		end
		if hovered then
			break
		end
	end
	if not hovered then
		return
	end
	Run(label .. " hover pin", function()
		hovered:OnMouseEnter()
		Flush()
	end)
	for _, key in ipairs({ "pins", "transit", "portals", "mapFlightMasters", "mapRoutes", "otherFaction" }) do
		for _, value in ipairs({ false, true }) do
			stats.settings = stats.settings + 1
			Run(("%s hovered setting %s=%s"):format(label, key, tostring(value)), function()
				ns.SetOption(key, value)
				Flush()
			end)
		end
	end
	Run(label .. " leave pin", function()
		hovered:OnMouseLeave()
		Flush()
	end)
end

-- The re-render a setting change drives, with the compass and route button live for this profile's state.
local function DrivePrime(label)
	Run(label .. " prime", function()
		ns.RefreshTracker()
		ns.RefreshMap()
		ns.RefreshMinimapPins()
		ns.RefreshCompass()
		ns.RefreshRouteButton()
		Flush()
		if ShortestPathForeverCompass and not ShortestPathForeverCompass.hidden then
			stats.compass = stats.compass + 1
		end
		if ShortestPathForeverRouteButton and not ShortestPathForeverRouteButton.hidden then
			stats.routeButton = stats.routeButton + 1
		end
	end)
	Run(label .. " prime tick", function()
		Advance(0.3)
	end)
end

local function DrivePaths(label)
	stats.paths = stats.paths + 1
	Run(label .. " public API estimate", function()
		ShortestPathForever.API.Estimate(1, 0.5, 0.5, 1414, 0.55, 0.5)
		ShortestPathForever.API.EstimateDetail(1, 0.5, 0.5, 1414, 0.55, 0.5)
	end)
	Run(label .. " refresh surfaces", function()
		ns.RefreshTracker()
		ns.RefreshMap()
		ns.RefreshMinimapPins()
		ns.RefreshCompass()
		ns.RefreshRouteButton()
		ns.RefreshTaxiRoute()
		ns.RefreshGuideStops()
		Flush()
		if ShortestPathForeverCompass and not ShortestPathForeverCompass.hidden then
			stats.compass = stats.compass + 1
		end
		if ShortestPathForeverRouteButton and not ShortestPathForeverRouteButton.hidden then
			stats.routeButton = stats.routeButton + 1
		end
	end)
	Run(label .. " guide toggle", function()
		ns.ToggleJourneyGuide()
		Flush()
		ns.ToggleJourneyGuide()
		Flush()
	end)
	Run(label .. " show on map", function()
		ns.ShowJourneyMap()
		Flush()
	end)
	Run(label .. " slash command", function()
		SlashCmdList.SHORTESTPATHFOREVER("")
		SlashCmdList.SHORTESTPATHFOREVER("perf")
		SlashCmdList.SHORTESTPATHFOREVER("debug")
		SlashCmdList.SHORTESTPATHFOREVER("debug")
		ShortestPathForever_OnAddonCompartmentClick()
		Flush()
	end)
end

--[[ Profiles: the representative states the task names, applied to the one live fixture. ]]
local function Reset()
	if ghost then
		ghost, corpsePosition = false, nil
		fireEvent("PLAYER_ALIVE")
		fireEvent("PLAYER_UNGHOST")
	end
	if combat then
		combat = false
		fireEvent("PLAYER_REGEN_ENABLED")
	end
	combat, onTaxi, ghost, corpsePosition, modifierDown, shiftDown = false, false, false, nil, false, false
	moving = false
	mapID, posMap, posX, posY, posZ, facing = 1414, 1, 0, 0, 0, 0
	zoom, cursorX, cursorY, visible, WorldMapFrame.shown = 1, 0.5, 0.5, true, true
	-- The settings drive below leaves every key off; a profile starts from the shipped defaults.
	for _, key in ipairs(SortedKeys(ns.Defaults)) do
		if ns.db[key] ~= ns.Defaults[key] then
			ns.SetOption(key, ns.Defaults[key])
		end
	end
	ns.ClearJourney()
	Flush()
end

local function Navigate(owner, stops)
	Run("plan " .. owner, function()
		assert(ShortestPathForever.API.NavigateRoute(owner, stops), owner .. " plans a route")
		Flush()
	end)
end

local function Single()
	return { { map = 1, x = 0.5, y = 0.5, title = "First" } }
end

local profiles = {
	{
		name = "bare",
		setup = function() end,
	},
	{
		name = "journey",
		setup = function()
			Navigate("Journey", Single())
		end,
	},
	{
		name = "route-inactive",
		setup = function()
			Navigate("Journey", Single())
			ns.ToggleJourneyGuide()
			Flush()
		end,
	},
	{
		name = "combat",
		setup = function()
			Navigate("Journey", Single())
			combat = true
			fireEvent("PLAYER_REGEN_DISABLED")
		end,
	},
	{
		name = "taxi",
		setup = function()
			Navigate("Journey", Single())
			onTaxi = true
			fireEvent("TAXIMAP_OPENED")
			fireEvent("TAXI_NODE_STATUS_CHANGED")
		end,
	},
	{
		name = "ghost",
		setup = function()
			Navigate("Journey", Single())
			ghost = true
			corpsePosition = CreateVector2D(0.5, 0.5)
			fireEvent("PLAYER_DEAD")
			Flush()
		end,
	},
	{
		name = "docks",
		setup = function()
			local dock = assert(ns.Docks[7], "the docks profile requires dock 7")
			posX, posY, posZ, posMap = dock.x + 60, dock.y, dock.z or 0, dock.map
			cursorX, cursorY = dock.x / 100000, dock.y / 100000
			ns.RefreshMinimapPins()
			Flush()
		end,
	},
	{
		name = "agf",
		setup = function()
			Navigate("AdventureGuideForever", {
				{ map = 1, x = 0.5, y = 0.5, title = "A", kind = "giver" },
				{ map = 1, x = 0.6, y = 0.6, title = "B", tooltip = "Clearing", hold = true },
			})
		end,
	},
	{
		name = "tweaks-v1",
		setup = function()
			Run("tweaks-v1 Navigate", function()
				assert(ShortestPathForever.API.Navigate("TweaksForever", 1, 0.5, 0.5, "Trainer"))
				Flush()
			end)
		end,
	},
	{
		name = "tweaks-v2",
		setup = function()
			Navigate("TweaksForever", {
				{ map = 1, x = 0.4, y = 0.4, title = "Trainer" },
				{ map = 1, x = 0.7, y = 0.7, title = "Vendor" },
			})
		end,
	},
	{
		name = "no-pins-map",
		setup = function()
			-- A zone with no dock, portal or flight point: the providers acquire nothing.
			mapID, posMap = 1234, 1234
			ns.RefreshMap()
			Flush()
		end,
	},
}

for _, profile in ipairs(profiles) do
	stats.profiles = stats.profiles + 1
	local label = profile.name
	Run(label .. " reset", function()
		Reset()
	end)
	Run(label .. " setup", function()
		profile.setup()
	end)
	DrivePrime(label)
	-- Drive the surfaces with the profile's route in place, then flip every setting and re-render.
	Run(label .. " frames", function()
		DriveFrames(label)
	end)
	Run(label .. " pins", function()
		DrivePins(label .. " map")
	end)
	Run(label .. " menus", function()
		DriveMenus(label)
	end)
	Run(label .. " paths", function()
		DrivePaths(label)
	end)
	Run(label .. " hovered setting", function()
		DriveHoveredSetting(label)
	end)
	Run(label .. " settings pages", function()
		DriveSettingsPages(label)
	end)
	Run(label .. " settings", function()
		DriveSettings(label)
	end)
	Run(label .. " re-render", function()
		ns.RefreshTracker()
		ns.RefreshMap()
		ns.RefreshCompass()
		ns.RefreshRouteButton()
		ns.RefreshMinimapPins()
		Advance(0.2)
	end)
	Run(label .. " frames after settings", function()
		DriveFrames(label .. " after")
	end)
	Run(label .. " pins after settings", function()
		DrivePins(label .. " after")
	end)
	Run(label .. " final", function() end)
end

--[[ A deterministic fuzz over the same objects: random settings, frames, pins, journeys and states, replayed
from one seed. A crash needing an unlikely combination still surfaces, named by its step. ]]
local seed = 20260930
local function Pick(count)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % count + 1
end

local function RandomFrame()
	local list = {}
	for _, frame in ipairs(frames) do
		if frame:IsVisible() and (Interactive(frame) or Hoverable(frame)) and Owned(frame) then
			list[#list + 1] = frame
		end
	end
	return list[Pick(#list)]
end

local function RandomPin()
	local list = {}
	for _, template in ipairs(SortedKeys(active)) do
		if template:match("^ShortestPathForever") then
			for _, pin in ipairs(active[template]) do
				if pin:IsShown() then
					list[#list + 1] = pin
				end
			end
		end
	end
	return list[Pick(#list)]
end

local function RandomSetting()
	local keys = SortedKeys(ns.Defaults)
	return keys[Pick(#keys)], Pick(2) == 1
end

local function Fuzz(label)
	local action = Pick(12)
	if action == 1 or action == 2 then
		local key, value = RandomSetting()
		stats.settings = stats.settings + 1
		Run(("%s setting %s=%s"):format(label, key, tostring(value)), function()
			ns.SetOption(key, value)
			Flush()
		end)
	elseif action == 3 then
		local frame = RandomFrame()
		if frame then
			local button = Pick(2) == 1 and "LeftButton" or "RightButton"
			Run(("%s frame %s click %s"):format(label, Name(frame), button), function()
				context = {}
				ClickFrame(frame, button)
				DrainContext(label)
				Flush()
			end)
		end
	elseif action == 4 then
		local frame = RandomFrame()
		if frame and Hoverable(frame) then
			local enter = Pick(2) == 1
			Run(("%s frame %s hover"):format(label, Name(frame)), function()
				HoverFrame(frame, enter)
			end)
		end
	elseif action == 5 then
		local pin = RandomPin()
		if pin then
			local method = Pick(3)
			Run(("%s pin %d"):format(label, method), function()
				if method == 1 and pin.OnMouseEnter then
					pin:OnMouseEnter()
				elseif method == 2 and pin.OnMouseLeave then
					pin:OnMouseLeave()
				elseif method == 3 and pin.OnClick then
					context = {}
					pin:OnClick("LeftButton")
					DrainContext(label)
				end
				Flush()
			end)
		end
	elseif action == 6 then
		Run(label .. " plan", function()
			local started = ShortestPathForever.API.NavigateRoute(
				"Fuzz",
				{ { map = 1, x = Pick(100) / 100, y = Pick(100) / 100, title = "Fuzz" } }
			)
			assert(started == (not combat and ns.db.journey == true), "fuzz route honours combat and journey setting")
			if started then
				assert(ShortestPathForever.API.CurrentStop("Fuzz") == 1, "fuzz route takes ownership")
			end
			Flush()
		end)
	elseif action == 7 then
		Run(label .. " guide", function()
			ns.ToggleJourneyGuide()
			Flush()
		end)
	elseif action == 8 then
		Run(label .. " clear", function()
			ShortestPathForever.API.Cancel("Fuzz")
			ns.ClearJourney()
			Flush()
		end)
	elseif action == 9 then
		Run(label .. " combat", function()
			combat = Pick(2) == 1
			fireEvent(combat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
			Flush()
		end)
	elseif action == 10 then
		Run(label .. " ghost", function()
			ghost = Pick(2) == 1
			corpsePosition = ghost and CreateVector2D(0.5, 0.5) or nil
			fireEvent(ghost and "PLAYER_DEAD" or "PLAYER_ALIVE")
			fireEvent(ghost and "PLAYER_DEAD" or "PLAYER_UNGHOST")
			Flush()
		end)
	elseif action == 11 then
		Run(label .. " taxi", function()
			onTaxi = Pick(2) == 1
			fireEvent("TAXIMAP_OPENED")
			Flush()
		end)
	else
		Run(label .. " map", function()
			mapID = ({ 1414, 1415, 1, 1234 })[Pick(4)]
			posX, posY, posMap = Pick(1000), Pick(1000), ({ 1, 0, 1415 })[Pick(3)]
			ns.RefreshMap()
			ns.RefreshMinimapPins()
			Flush()
		end)
	end
end

Reset()
Run("stale dock cluster tooltip", function()
	local cluster = {
		docks = { { id = 999998 }, { id = 999999 } },
		kinds = { boat = true, lift = true },
	}
	assert(#ns.DockDepartures(999998) == 0 and #ns.DockDepartures(999999) == 0,
		"the stale cluster has no remaining departures")
	ns.AddDockTooltip(cluster)
end)
stats.profiles = stats.profiles + 1
for step = 1, 400 do
	Fuzz(("fuzz %d"):format(step))
end

if #failures > 0 then
	error(("%d smoke failure(s):\n%s"):format(#failures, table.concat(failures, "\n")), 0)
end

for key, value in pairs(stats) do
	assert(value > 0, "the smoke sweep did not exercise " .. key)
end

print(("smoke_spec: %d checks passed; %d profile runs, %d frames, %d clicks, %d hovers, %d menus, %d pins, "
	.. "%d setting writes, %d settings rows, %d index buttons, %d planning paths, %d compass renders, "
	.. "%d route-button renders"):format(checks, stats.profiles, stats.frames, stats.clicks, stats.hovers,
	stats.menus, stats.pins, stats.settings, stats.rows, stats.buttons, stats.paths, stats.compass,
	stats.routeButton))
]==]))()
