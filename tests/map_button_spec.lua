-- Nearby services quick map button (#1342): drawn through UI/Canvas.lua on our own frame (never AddOverlayFrame),
-- native art through UI/Art.lua, left-click toggles Nearby services, right-click opens a scrollable checkbox menu
-- bound to the same service filter settings as the Nearby services panel.
local source = ""
for _, part in ipairs({ "tests/ui_client.lua", "tests/ui_map.lua" }) do
	local file = assert(io.open(part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [==[
local button = assert(ns.nearbyMapButton, "Nearby services map button is created on WorldMapFrame")
assert(button.parent == WorldMapFrame, "button is parented to WorldMapFrame through Canvas.FrameUnder")
assert(button:IsShown(), "button is shown by default (nearbyMapButton = true)")
assert(ns.Defaults.nearbyMapButton == true and ns.db.nearbyMapButton == true, "nearbyMapButton defaults on")
assert(button.scripts.OnShow == nil and button.scripts.OnHide == nil, "no OnShow or OnHide script under WorldMapFrame")
assert(
	button.Background and button.Background.atlas == "common-button-square-gray-up",
	"native set-1 square button frame"
)
assert(button.Icon and button.Icon.atlas == "Banker", "button wears the Nearby services Banker atlas via Art.Fit")
assert(button.Highlight and button.Highlight.atlas == "common-button-square-gray-up", "native hover highlight")

-- Setting toggles button visibility cleanly.
ns.db.nearbyMapButton = false
ns.RefreshMapButton()
assert(not button:IsShown(), "turning nearbyMapButton off hides the button")
ns.db.nearbyMapButton = true
ns.RefreshMapButton()
assert(button:IsShown(), "turning nearbyMapButton back on shows the button")

-- Positioning: stacks cleanly below shown TOPRIGHT overlay frames and below Legacy Forever's map button.
mapID, zoom = 1414, 1
setMapShown(true)
assert(button.anchor and button.anchor[1] == "TOPRIGHT" and button.anchor[5] == -2, "anchored at TOPRIGHT (-4, -2)")
local fakeOverlay = {
	IsShown = function() return true end,
	GetPoint = function() return "TOPRIGHT" end,
}
WorldMapFrame.overlayFrames = { fakeOverlay }
ns.RefreshMapButton()
assert(button.anchor[5] == -34, "shifts down below a shown TOPRIGHT overlay frame")
_G.LegacyForeverMapButtonMixin = {}
ns.RefreshMapButton()
assert(button.anchor[5] == -80, "shifts below Legacy Forever's top-right shield when loaded")
_G.LegacyForeverMapButtonMixin = nil
WorldMapFrame.overlayFrames = nil
ns.RefreshMapButton()
assert(button.anchor[5] == -2, "returns to top slot when alone")

-- Pressed look and tooltip.
button.scripts.OnMouseDown(button, "LeftButton")
assert(button.Background.atlas == "common-button-square-gray-down", "mouse down shows pressed button frame")
button.scripts.OnMouseUp(button, "LeftButton")
assert(button.Background.atlas == "common-button-square-gray-up", "mouse up restores normal button frame")

button.scripts.OnEnter(button)
assert(GameTooltip:IsShown() and GameTooltip:IsOwned(button), "hover shows tooltip owned by button")
local joined = table.concat(tip, "\n")
assert(joined:find("Nearby services", 1, true), "tooltip titles Nearby services")
assert(joined:find("Left-click to toggle Nearby services.", 1, true), "tooltip documents left-click")
assert(joined:find("Right-click to choose map services.", 1, true), "tooltip documents right-click")
button.scripts.OnLeave(button)
assert(not GameTooltip:IsShown(), "leave hides tooltip")

-- Closing the map clears any owned tooltip via Canvas.Watch without an OnHide script.
button.scripts.OnEnter(button)
assert(GameTooltip:IsShown(), "tooltip open before map hide")
setMapShown(false)
assert(not GameTooltip:IsShown(), "map hide clears button tooltip")
setMapShown(true)

-- Left-click opens/toggles the Nearby services panel through ForeverCore.QuestLogTabs.
local selectedKey, selectCalls, showQuestsCalls, requestCalls = nil, 0, 0, 0
local savedTabs = _G.ForeverCore.QuestLogTabs
_G.ForeverCore.QuestLogTabs = {
	Selected = function() return selectedKey end,
	Select = function(key)
		selectedKey = key
		selectCalls = selectCalls + 1
	end,
	ShowQuests = function()
		selectedKey = nil
		showQuestsCalls = showQuestsCalls + 1
	end,
}
local groups = {
	{ section = "vendors", key = "arrows", label = "Arrows", tracking = "Ammunition" },
	{ section = "vendors", key = "food", label = "Food", tracking = "Food" },
	{ section = "trainers", key = "class", label = "Class trainer", tracking = "Class" },
	{ section = "services", key = "bank", label = "Bank", tracking = "Banker" },
	{ section = "services", key = "flight", label = "Flight master", tracking = "FlightMaster" },
	{ section = "entrances", key = "entrance:36", label = "The Deadmines", tracking = "Dungeon" },
}
local place = { id = 1, name = "NPC", map = 14, x = 0.5, y = 0.5, world = { map = 1, x = 0, y = 0 } }
local index = { arrows = { place }, food = { place }, class = { place }, bank = { place }, flight = { place } }
local state = "ready"
ns.NearbyServices = {
	Request = function() requestCalls = requestCalls + 1 end,
	State = function() return state end,
	Index = function() return index end,
	Groups = function() return groups end,
}
local mapInfo = C_Map.GetMapInfo
C_Map.GetMapInfo = function(id)
	local info = mapInfo(id)
	info.mapType = Enum.UIMapType.Zone
	return info
end

button.scripts.OnClick(button, "LeftButton")
assert(selectedKey == "services" and selectCalls == 1 and requestCalls == 1, "first left-click selects services panel")
button.scripts.OnClick(button, "LeftButton")
assert(selectedKey == nil and showQuestsCalls == 1, "second left-click toggles panel closed back to quests")
button.scripts.OnClick(button, "LeftButton")
assert(selectedKey == "services" and selectCalls == 2, "third left-click opens services panel again")

-- Right-click opens ForeverCore.ContextMenu with scrolling, section headings, checkboxes per service, and town levels.
local function captureMenu()
	local entries, scrollExtent, menuOwner = {}, nil, nil
	local function makeRoot(list)
		local desc = {}
		function desc:SetScrollMode(extent)
			scrollExtent = extent
		end
		function desc:CreateTitle(text)
			list[#list + 1] = { kind = "title", text = text }
			return list[#list]
		end
		function desc:CreateDivider()
			list[#list + 1] = { kind = "divider" }
			return list[#list]
		end
		function desc:CreateCheckbox(label, get, click)
			local item = { kind = "checkbox", label = label, get = get, click = click }
			list[#list + 1] = item
			return item
		end
		function desc:CreateRadio(label, get, click)
			local item = { kind = "radio", label = label, get = get, click = click }
			list[#list + 1] = item
			return item
		end
		function desc:CreateButton(label, click)
			local sub = {}
			local item = makeRoot(sub)
			item.kind, item.label, item.click, item.children = "button", label, click, sub
			list[#list + 1] = item
			return item
		end
		return desc
	end
	local savedContextMenu = _G.ForeverCore.ContextMenu
	_G.ForeverCore.ContextMenu = function(owner, generator)
		menuOwner = owner
		local root = makeRoot(entries)
		generator(owner, root)
	end
	button.scripts.OnClick(button, "RightButton")
	_G.ForeverCore.ContextMenu = savedContextMenu
	return entries, scrollExtent, menuOwner
end

ns.db.townServices = "off"
ns.db.townServiceKinds = {}
ns.db.mapFlightMasters = true
local entries, scrollExtent, menuOwner = captureMenu()
assert(menuOwner == button, "context menu is owned by the map button")
assert(scrollExtent == 400, "right-click menu scrolls past 20 rows (WFA-36)")

local boxes, titles, townSub = {}, {}, nil
for _, entry in ipairs(entries) do
	if entry.kind == "checkbox" then
		boxes[entry.label] = entry
		boxes[#boxes + 1] = entry
	elseif entry.kind == "title" then
		titles[#titles + 1] = entry.text
	elseif entry.kind == "button" and entry.label == "Town services" then
		townSub = entry
	end
end
assert(#boxes == 5, "one checkbox per filterable service kind plus Flight master, excluding entrances")
assert(boxes["The Deadmines"] == nil, "dungeon entrances are excluded from service checkboxes")
assert(boxes["Arrows"] and boxes["Food"] and boxes["Class trainer"] and boxes["Bank"] and boxes["Flight master"],
	"every filterable service kind has a checkbox")
assert(
	titles[1] == "Nearby services"
		and titles[2] == "Vendors"
		and titles[3] == "Trainers"
		and titles[4] == "Services",
	"menu titles group checkboxes by Nearby services sections"
)

-- While townServices is off, town service checkboxes read false and Flight master reads mapFlightMasters.
assert(boxes["Arrows"].get() == false and boxes["Bank"].get() == false, "town services unticked while layer is off")
assert(boxes["Flight master"].get() == true, "flight master checkbox reads mapFlightMasters")

-- Ticking a service when layer is off turns townServices to "all" with only that service ticked (same as panel).
boxes["Arrows"].click()
assert(ns.db.townServices == "all", "ticking a service turns town services on")
assert(boxes["Arrows"].get() == true, "ticked service now reads checked")
assert(boxes["Bank"].get() == false, "other services stay unchecked")
assert(ns.ServiceOnMap(groups[1]) == true and ns.ServiceOnMap(groups[4]) == false, "panel settings match menu")

-- Ticking a second service enables it without clearing the first; unticking turns it back off.
boxes["Bank"].click()
assert(boxes["Bank"].get() == true and boxes["Arrows"].get() == true, "second service ticks independently")
boxes["Arrows"].click()
assert(boxes["Arrows"].get() == false and boxes["Bank"].get() == true, "unticking clears only that service")

-- Flight master checkbox toggles mapFlightMasters without touching townServiceKinds.
boxes["Flight master"].click()
assert(ns.db.mapFlightMasters == false and boxes["Flight master"].get() == false, "flight master toggles off")
assert(ns.db.townServiceKinds.flight == nil, "flight master is stored in mapFlightMasters, not townServiceKinds")
boxes["Flight master"].click()
assert(ns.db.mapFlightMasters == true and boxes["Flight master"].get() == true, "flight master toggles back on")

-- Town services level submenu radios change townServices level.
assert(townSub and #townSub.children == 4, "Town services submenu holds the four town levels")
local offRadio
for _, child in ipairs(townSub.children) do
	if child.label == OFF then
		offRadio = child
	end
end
assert(offRadio and not offRadio.get(), "Off radio starts unselected while layer is on")
offRadio.click()
assert(ns.db.townServices == "off" and offRadio.get(), "clicking Off turns town services off")
assert(boxes["Bank"].get() == false, "service checkbox reads unchecked once layer is off")

-- While QuestieDB is not ready, menu shows the status message without erroring.
state = "missing"
local missingEntries = captureMenu()
local sawStatus = false
for _, entry in ipairs(missingEntries) do
	if entry.kind == "title" and entry.text == "Nearby services need the QuestieDB addon." then
		sawStatus = true
	end
end
assert(sawStatus, "right-click menu reports missing QuestieDB cleanly")
state = "ready"

-- Under gamepad interface, clicks post the notice and neither open the panel nor open a context menu.
local savedGamepad = ns.GamepadUI
local notices = {}
local savedNotice = ns.Notice
ns.GamepadUI = function() return true end
ns.Notice = function(msg) notices[#notices + 1] = msg end
local beforeSelect = selectCalls
local openedInGamepad = false
local savedCM = _G.ForeverCore.ContextMenu
_G.ForeverCore.ContextMenu = function() openedInGamepad = true end
button.scripts.OnClick(button, "LeftButton")
button.scripts.OnClick(button, "RightButton")
assert(selectCalls == beforeSelect and not openedInGamepad, "gamepad clicks neither switch tabs nor open menus")
assert(#notices == 2 and notices[1] == "This menu needs mouse and keyboard.", "gamepad clicks tell the player")
_G.ForeverCore.ContextMenu = savedCM
ns.GamepadUI, ns.Notice = savedGamepad, savedNotice
_G.ForeverCore.QuestLogTabs = savedTabs

print("map_button_spec: passed")
]==]))()
