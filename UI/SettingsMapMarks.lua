---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- The Map marks page: what the world map and the minimap draw, and how the walking line is drawn. UI/Settings.lua
-- owns the category and the row builders; a page module opens its own page and adds its rows through them, so every
-- row still registers through Blizzard's secure initializer and ns.SetOption finds it.

---@class SPFSettingsMapMarks
local MapMarks = {}
ns.SettingsMapMarks = MapMarks

---@param rows SPFSettingsRows
function MapMarks.Register(rows)
	rows.Page(L["Map marks"])
	rows.Checkbox("pins", L["Show boats and zeppelins"], L["On the world map."], ns.RefreshMap)
	rows.Checkbox(
		"transit",
		L["Show lifts and the tram"],
		L["Lifts and the Deeprun Tram, on the world map."],
		ns.RefreshMap
	)
	rows.Checkbox("portals", L["Show portals"], L["On the world map."], ns.RefreshMap)
	rows.Checkbox("mapFlightMasters", L["Show flight masters"], L["On the world map."], ns.RefreshMap)
	rows.Checkbox(
		"nearbyTab",
		L["Show the Nearby services tab"],
		L["The tab in the world map's quest log. Off, /spfnear and the tracking menu still open it."],
		ns.RefreshNearbyTab
	)
	rows.Checkbox(
		"minimapPins",
		L["Show marks on the minimap"],
		L["Docks, lifts, the tram and portals. Also under Transport in the minimap's tracking menu."],
		ns.RefreshMinimapPins
	)
	rows.Checkbox(
		"hideQuestPins",
		L["Hide game quest markers"],
		L["Off, the game's own quest markers stay beside your journey's pins, showing the other places a quest can be done."],
		ns.RefreshQuestPins
	)

	rows.Scale(
		"mapPinScale",
		L["Transport icon size"],
		L["Sizes boat, lift, tram and portal icons on the world map."],
		ns.RefreshMap
	)
	rows.Scale(
		"flightPinScale",
		L["Flight master icon size"],
		L["Sizes flight master icons on the world map."],
		ns.RefreshMap
	)
	rows.Scale(
		"minimapPinScale",
		L["Minimap icon size"],
		L["Sizes transport icons on the minimap."],
		ns.RefreshMinimapPins
	)

	-- Town services: one icon per town zoomed out, one per service zoomed in, filtered by how much of a town you want
	-- on the map. Off and the three levels match the world map's own filter submenu.
	rows.Dropdown(
		"townServices",
		L["Town services on the world map"],
		L["One icon per town, or one per service as you zoom in."],
		ns.TownServiceChoices,
		ns.RefreshTownServices
	)
	rows.Checkbox(
		"onlyMyProfessions",
		L["Only my professions"],
		L["Hides profession trainers and their supply vendors for professions this character has not learned."]
			.. " "
			.. L["On the world map and in Nearby services."],
		function()
			ns.RefreshMap()
			if type(ns.RefreshServiceFilters) == "function" then
				ns.RefreshServiceFilters()
			end
		end
	)

	-- The walking line's colour, so it stays apart from the herbs and ore a player is gathering.
	rows.Dropdown(
		"routeColor",
		L["Walking route colour"],
		L["The walking line on the world map and the minimap."],
		ns.RouteColors,
		function(_, value)
			ns.SetRouteColor(type(value) == "string" and value or nil)
		end
	)
	rows.Checkbox(
		"mapLine",
		L["Line on the world map"],
		L["Draws the walking route on the world map. With it off, the destination pin, arrow and tracker still guide you."],
		ns.RefreshRouteLines
	)
	rows.Checkbox(
		"minimapLine",
		L["Line on the minimap"],
		L["Draws the walking route on the minimap. With it off, the destination pin, arrow and tracker still guide you."],
		ns.RefreshRouteLines
	)
	rows.Checkbox(
		"laterLegs",
		L["Line to later stops"],
		L["Draws the legs after the current stop, faded, on the world map. Off, only the current leg and the pins stay."],
		ns.RefreshJourneyPreview
	)
end
