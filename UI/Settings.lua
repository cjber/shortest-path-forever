local addonName = ...
---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

local settings = {}

-- Change an option from anywhere (the map's filter menu) with the settings panel kept in step.
---@param key string
---@param value boolean|number|string
function ns.SetOption(key, value)
	settings[key]:SetValue(value)
end

local category

-- The settings category is the addon's one options surface: the slash command and the compartment entry open it.
-- Through ForeverCore's secure opener: the client's Settings.OpenToCategory and its C_SettingsUtil.OpenSettingsPanel
-- refuse a direct call from addon code (cjber/forever-core#333).
function ns.OpenSettings()
	ForeverCore.OpenSettingsPanel(category:GetID())
end

local optionsButton
function ns.RefreshOptionsButton()
	if ns.db.minimapButton and not optionsButton then
		-- Named: a template button under an unnamed frame gives its `$parent` label a bare global name
		-- (`MinimapText` here), which another addon or a Blizzard layout could read as its own (#457).
		optionsButton = CreateFrame("Button", "ShortestPathForeverOptionsButton", Minimap, "SharedButtonSmallTemplate")
		optionsButton:SetSize(70, 22)
		optionsButton:SetPoint("TOP", Minimap, "BOTTOM", 0, -2)
		optionsButton:SetText(L["Journey"])
		optionsButton:SetScript("OnClick", ns.OpenSettings)
		optionsButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip_SetTitle(GameTooltip, "Shortest Path Forever")
			GameTooltip_AddNormalLine(GameTooltip, L["Open settings."])
			GameTooltip:Show()
		end)
		optionsButton:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end
	if optionsButton then
		optionsButton:SetShown(ns.db.minimapButton)
	end
end

local function Perf()
	local profiler, metrics = C_AddOnProfiler, Enum.AddOnProfilerMetric
	if profiler and profiler.GetAddOnMetric and metrics and (not profiler.IsEnabled or profiler.IsEnabled()) then
		for _, entry in ipairs({
			{ "RecentAverageTime", "recent average (60 ticks)" },
			{ "SessionAverageTime", "session average" },
			{ "LastTime", "last tick" },
			{ "PeakTime", "session peak" },
		}) do
			if metrics[entry[1]] then
				ns.Print(
					string.format("CPU %s: %.3f ms", entry[2], profiler.GetAddOnMetric(addonName, metrics[entry[1]]))
				)
			end
		end
		if metrics.CountTimeOver5Ms then
			ns.Print(string.format("Ticks over 5 ms: %d", profiler.GetAddOnMetric(addonName, metrics.CountTimeOver5Ms)))
		end
	else
		ns.Print("CPU profiling is unavailable on this client.")
	end
	-- Updating memory walks every addon's allocations, so only do it on this explicit request.
	if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		collectgarbage("collect")
		UpdateAddOnMemoryUsage()
		ns.Print(string.format("Memory (collected): %.1f KB", GetAddOnMemoryUsage(addonName) or 0))
	else
		ns.Print("Memory accounting is unavailable on this client.")
	end
end

-- Rows go in through Settings.RegisterInitializer, which inserts them from Blizzard's secure delegate.
-- Settings.CreateCheckbox inserts from our code instead, and the settings search reads every layout, so that
-- tainted it: a restricted button in the results (Social's Discord Sign In) was then blocked and blamed on us.
ns.Init(function()
	category = Settings.RegisterVerticalLayoutCategory("Shortest Path Forever")

	-- Topic → AddOns → Shortest Path Forever: a short index page of buttons, then a stock subpage per group so no
	-- page grows tall. The index buttons stay out of the settings search (the last argument) so it finds the
	-- settings themselves.
	local page
	local function Page(name)
		local subcategory = Settings.RegisterVerticalLayoutSubcategory(category, name)
		page = subcategory
		Settings.RegisterInitializer(
			category,
			CreateSettingsButtonInitializer(name, L["Open"], function()
				ForeverCore.OpenSettingsPanel(subcategory:GetID())
			end, nil, false)
		)
	end

	local function Checkbox(key, name, tooltip, onChanged)
		local setting = Settings.RegisterAddOnSetting(
			page,
			"ShortestPathForever_" .. key,
			key,
			ns.db,
			Settings.VarType.Boolean,
			name,
			ns.Defaults[key]
		)
		if onChanged then
			setting:SetValueChangedCallback(onChanged)
		end
		Settings.RegisterInitializer(page, Settings.CreateCheckboxInitializer(setting, nil, tooltip))
		settings[key] = setting
	end

	local function Scale(key, name, tooltip, refresh)
		local setting = Settings.RegisterAddOnSetting(
			page,
			"ShortestPathForever_" .. key,
			key,
			ns.db,
			Settings.VarType.Number,
			name,
			ns.Defaults[key]
		)
		setting:SetValueChangedCallback(refresh)
		settings[key] = setting
		local options = Settings.CreateSliderOptions(25, 200, 5)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return value .. "%"
		end)
		Settings.RegisterInitializer(page, Settings.CreateSliderInitializer(setting, options, tooltip))
	end

	-- Map marks: what the world map and the minimap draw.
	Page(L["Map marks"])
	Checkbox("pins", L["Show boats and zeppelins"], L["On the world map."], ns.RefreshMap)
	Checkbox("transit", L["Show lifts and the tram"], L["Lifts and the Deeprun Tram, on the world map."], ns.RefreshMap)
	Checkbox("portals", L["Show portals"], L["On the world map."], ns.RefreshMap)
	Checkbox("mapFlightMasters", L["Show flight masters"], L["On the world map."], ns.RefreshMap)
	Checkbox(
		"minimapPins",
		L["Show marks on the minimap"],
		L["Docks, lifts, the tram and portals. Also under Transport in the minimap's tracking menu."],
		ns.RefreshMinimapPins
	)

	Scale(
		"mapPinScale",
		L["Transport icon size"],
		L["Sizes boat, lift, tram and portal icons on the world map."],
		ns.RefreshMap
	)
	Scale(
		"flightPinScale",
		L["Flight master icon size"],
		L["Sizes flight master icons on the world map."],
		ns.RefreshMap
	)
	Scale("minimapPinScale", L["Minimap icon size"], L["Sizes transport icons on the minimap."], ns.RefreshMinimapPins)

	-- Town services: one icon per town zoomed out, one per service zoomed in, filtered by how much of a town you want
	-- on the map. Off and the three levels match the world map's own filter submenu.
	local townServices = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_townServices",
		"townServices",
		ns.db,
		Settings.VarType.String,
		L["Town services on the world map"],
		ns.Defaults.townServices
	)
	townServices:SetValueChangedCallback(ns.RefreshTownServices)
	settings.townServices = townServices
	local townOptions = Settings.CreateControlTextContainer()
	for _, choice in ipairs(ns.TownServiceChoices) do
		townOptions:Add(choice.key, choice.label)
	end
	Settings.RegisterInitializer(
		page,
		Settings.CreateDropdownInitializer(townServices, function()
			return townOptions:GetData()
		end, L["One icon per town, or one per service as you zoom in."])
	)

	-- The walking line's colour, so it stays apart from the herbs and ore a player is gathering.
	local routeColor = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_routeColor",
		"routeColor",
		ns.db,
		Settings.VarType.String,
		L["Walking route colour"],
		ns.Defaults.routeColor
	)
	routeColor:SetValueChangedCallback(function(_, value)
		ns.SetRouteColor(type(value) == "string" and value or nil)
	end)
	settings.routeColor = routeColor
	local routeColorOptions = Settings.CreateControlTextContainer()
	for _, choice in ipairs(ns.RouteColors) do
		routeColorOptions:Add(choice.key, choice.label)
	end
	Settings.RegisterInitializer(
		page,
		Settings.CreateDropdownInitializer(routeColor, function()
			return routeColorOptions:GetData()
		end, L["The walking line on the world map and the minimap."])
	)
	Checkbox(
		"mapLine",
		L["Line on the world map"],
		L["Draws the walking route on the world map. With it off, the destination pin, arrow and tracker still guide you."],
		ns.RefreshRouteLines
	)
	Checkbox(
		"minimapLine",
		L["Line on the minimap"],
		L["Draws the walking route on the minimap. With it off, the destination pin, arrow and tracker still guide you."],
		ns.RefreshRouteLines
	)

	-- Transport: routes and departure times.
	Page(L["Transport"])
	Checkbox(
		"mapRoutes",
		L["Show routes on the world map"],
		L["Boat and zeppelin routes, drawn while you point at a dock."],
		ns.RefreshMap
	)
	Checkbox(
		"otherFaction",
		L["Show other faction's routes"],
		L["Either faction can ride any boat or zeppelin."],
		function()
			ns.RefreshMap()
			ns.RefreshTracker()
		end
	)
	Checkbox(
		"tracker",
		L["Show boat, lift and tram departures in the tracker"],
		L["In the objective tracker while you are near a dock, lift or tram."],
		ns.RefreshTracker
	)
	Checkbox(
		"share",
		L["Share departure times"],
		L["Sends and receives sighting times over guild, party and at the dock. No chat messages are shown."]
	)

	Page(L["Travel journal"])
	Checkbox(
		"stats",
		L["Record travel stats"],
		L["On by default. Records approximate walking distance, completed journeys and transport use."],
		ns.TravelSharingChanged
	)
	Checkbox(
		"statsShare",
		L["Share travel stats with guild and groups"],
		L["On unless you turn it off. Shares travel records with guild and group and puts you on Forever Leaderboards."]
			.. " "
			.. L["Turn this off to keep stats on this character only. Shared records are player-reported and not verified."],
		ns.TravelSharingChanged
	)

	-- Guidance: how a journey is planned and led.
	Page(L["Guidance"])
	local host = ForeverCore.TrackerHost --[[@as ForeverTrackerHostAPI]]
	local variable = "ShortestPathForever_trackerAttached"
	local attachment = Settings.RegisterProxySetting(
		page,
		variable,
		Settings.VarType.Boolean,
		L["Attach to quest tracker"],
		true,
		function()
			return host.GetSettings().attached
		end,
		function(value)
			host.SetAttached(value == true)
		end
	)
	Settings.RegisterInitializer(
		page,
		Settings.CreateCheckboxInitializer(
			attachment,
			nil,
			L["Turn this off to drag the shared Forever tracker anywhere on screen."]
		)
	)
	host.OnAttachmentChanged(function()
		Settings.NotifyUpdate(variable)
	end)
	-- Lock keeps the detached column where it is: the grip ignores drag while it is on. Off by default, and safe to
	-- toggle in combat, since it only writes the saved switch.
	local lock = Settings.RegisterProxySetting(
		page,
		"ShortestPathForever_trackerLocked",
		Settings.VarType.Boolean,
		L["Lock the tracker"],
		false,
		function()
			return host.GetSettings().locked == true
		end,
		function(value)
			host.SetLocked(value == true)
		end
	)
	Settings.RegisterInitializer(
		page,
		Settings.CreateCheckboxInitializer(
			lock,
			nil,
			L["Keeps the shared Forever tracker where you put it. The grip at its top no longer drags it."]
		)
	)
	Checkbox(
		"journey",
		L["Shift-click to plan journeys"],
		L["Shift-click the world map or the minimap to plan a journey there."],
		function()
			if not ns.db.journey then
				ns.ClearJourney()
			end
			-- The guide follower only ticks while journeys are on; turning them back on starts it again.
			ns.RefreshGuidelime()
		end
	)
	Checkbox(
		"journeyTracker",
		L["Show journey steps in the objective tracker"],
		L["Off keeps the arrow, pin, map line and minimap route, with no journey block in the objective tracker."],
		ns.RefreshTracker
	)
	Checkbox(
		"resumeJourney",
		L["Keep journeys after a reload"],
		L["Your own journey starts again after a /reload, or logging back in within 30 minutes. Guides start theirs."],
		function()
			ns.KeepJourneyChanged()
		end
	)
	Checkbox(
		"destinationPin",
		L["Show a pin over the destination"],
		L["A marker on screen over where the journey ends, like the game's own waypoint pin."]
			.. " "
			.. L["It stands down while Waypoint UI is navigating, so the two never draw over each other."],
		function()
			ns.DestinationPinChanged()
		end
	)
	Checkbox(
		"arrivalPin",
		L["Show a pin when you reach a stop"],
		L["In a stop's area the direction arrow becomes a pin with the stop's objectives, instead of hiding."]
			.. " "
			.. L["It returns to the arrow when you leave the area or the stop changes."],
		ns.ArrivalPinChanged
	)
	local arrivalDistance = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_arrivalDistance",
		"arrivalDistance",
		ns.db,
		Settings.VarType.Number,
		L["Arrival distance"],
		ns.Defaults.arrivalDistance
	)
	settings.arrivalDistance = arrivalDistance
	local arrivalOptions = Settings.CreateSliderOptions(5, 50, 5)
	arrivalOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ns.FormatDistance(value)
	end)
	Settings.RegisterInitializer(
		page,
		Settings.CreateSliderInitializer(
			arrivalDistance,
			arrivalOptions,
			L["How close you must get to a journey's destination for it to count as reached."]
				.. " "
				.. L["Stops before the last on a multi-stop route keep 15 yards."]
		)
	)
	Checkbox(
		"npcArrows",
		L["Arrows on the NPC's nameplate"],
		L["Shows over the nameplate of the NPC a Nearby services journey walks to."]
			.. " "
			.. L["Friendly nameplates must be on to see them."],
		function()
			ns.RefreshNpcArrows()
		end
	)
	Checkbox(
		"tomtom",
		L["Let guides set TomTom waypoints"],
		L["While TomTom is not installed, a guide that sets a TomTom waypoint starts a journey here instead."],
		function()
			ns.RefreshTomTom()
		end
	)
	Checkbox(
		"tomtomFollow",
		L["Follow TomTom's arrow"],
		L["With TomTom installed, a journey here follows the waypoint its arrow points to."],
		function()
			ns.RefreshTomTomFollow()
		end
	)
	Checkbox(
		"restedxp",
		L["Follow RestedXP guides"],
		L["Plan journeys to RestedXP guide targets and hide its arrow. No TomTom needed."],
		function()
			ns.RefreshRestedXP()
		end
	)
	Checkbox(
		"restedxpHideArrow",
		L["Hide RestedXP's arrow"],
		L["Shortest Path's own arrow replaces the guide's while a guide target is followed."]
			.. " "
			.. L["Turning this off leaves RestedXP's arrow visible."],
		function()
			ns.RefreshRestedXP()
		end
	)
	Checkbox(
		"guidelime",
		L["Follow Guidelime guides"],
		L["Plan journeys to Guidelime's current guide step. Guidelime's arrow steps aside while ours draws."],
		function()
			ns.RefreshGuidelime()
		end
	)
	Checkbox(
		"avoidHighZones",
		L["Avoid zones far above my level"],
		L["Walks go round zones whose lowest level is 4 or more above yours, but never the ones you start or end in."],
		ns.TravelPolicyChanged
	)
	Checkbox(
		"followRoads",
		L["Follow roads"],
		-- luacheck: push ignore 631
		L["Walks keep to roads and paved streets where that adds less than half again to the walk. Roads painted with a zone's plain dirt are not known."],
		-- luacheck: pop
		ns.TravelPolicyChanged
	)
	Checkbox(
		"teleports",
		L["Use hearth and teleports"],
		L["Journeys, and other addons' estimates from here, can start with your hearthstone or a teleport, cooldown counted."]
	)
	local hearth = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_hearthMinimumSavings",
		"hearthMinimumSavings",
		ns.db,
		Settings.VarType.Number,
		L["Minimum Hearthstone saving"],
		ns.Defaults.hearthMinimumSavings
	)
	hearth:SetValueChangedCallback(ns.TravelPolicyChanged)
	settings.hearthMinimumSavings = hearth
	local hearthOptions = Settings.CreateSliderOptions(0, 600, 30)
	hearthOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return value > 0 and SecondsToTime(value) or OFF
	end)
	Settings.RegisterInitializer(
		page,
		Settings.CreateSliderInitializer(
			hearth,
			hearthOptions,
			L["Only use the Hearthstone when it saves at least this much time."]
		)
	)
	Checkbox(
		"guideStops",
		L["Mark only where steps end"],
		L["Guide marks the next boat, lift, flight master or your destination, not each turn of the walk on the way."],
		ns.RefreshGuideStops
	)
	Checkbox(
		"taxiRoute",
		L["Show the flight to take"],
		L["Your journey's next flight is drawn on the flight master's map, with its destination lit up."],
		ns.RefreshTaxiRoute
	)
	Checkbox(
		"corpse",
		L["Show the way to your corpse"],
		L["While you are a ghost, a red dotted path leads to your body. Your journey waits until you are alive again."],
		ns.RefreshCorpseRun
	)

	Settings.RegisterInitializer(
		page,
		CreateSettingsButtonInitializer(L["RestedXP guide"], L["Resume guide"], function()
			ns.ResumeRestedXP()
		end, nil, false)
	)
	Settings.RegisterInitializer(
		page,
		CreateSettingsButtonInitializer(L["Guidelime"], L["Resume guide"], function()
			ns.ResumeGuidelime()
		end, nil, false)
	)

	-- Party portals: another player's mage portals, declared because the client cannot read their spellbook. The
	-- planner only offers them while another mage is in the party or raid.
	Page(L["Party mage portals"])
	Checkbox(
		"partyMagePortals",
		L["Ask a mage in my group for portals"],
		L["Only when another mage is in your party or raid. A portal is offered when it shortens the journey."]
			.. " "
			.. L["Only your faction's capital portals are used."],
		ns.TravelPolicyChanged
	)
	Checkbox("partyMageStormwind", L["Stormwind"], L["The mage can open a portal here."], ns.TravelPolicyChanged)
	Checkbox("partyMageIronforge", L["Ironforge"], L["The mage can open a portal here."], ns.TravelPolicyChanged)
	Checkbox("partyMageDarnassus", L["Darnassus"], L["The mage can open a portal here."], ns.TravelPolicyChanged)
	Checkbox("partyMageUndercity", L["Undercity"], L["The mage can open a portal here."], ns.TravelPolicyChanged)
	Checkbox("partyMageThunderBluff", L["Thunder Bluff"], L["The mage can open a portal here."], ns.TravelPolicyChanged)
	Checkbox("partyMageOrgrimmar", L["Orgrimmar"], L["The mage can open a portal here."], ns.TravelPolicyChanged)

	-- Alerts: the arrival warning.
	Page(L["Alerts"])
	Checkbox(
		"alerts",
		L["Alert before a boat arrives"],
		L["While you wait at a dock or ride a timed boat: a warning on screen and a flashing taskbar icon."]
	)
	Checkbox(
		"flightPathReminder",
		L["Remind me about new flight masters"],
		L["Warns when a journey needs you to discover a flight master, and again when you are close."]
	)
	Checkbox("alertSound", L["Play a sound with alerts"], L["Plays even with the game in the background."])
	Checkbox(
		"arrivalSound",
		L["Play a sound when you reach the goal"],
		L["The map's ping when a journey you planned reaches its goal, even with the game in the background."]
	)

	-- Interface: what the addon puts on screen.
	Page(L["Interface"])
	Checkbox(
		"arrow",
		L["Show direction arrow"],
		L["Show the next direction and the game's navigation marker."],
		function()
			ns.JourneyGuide.Retarget()
			ns.WakeTravel()
		end
	)
	Settings.RegisterInitializer(
		page,
		Settings.CreateCheckboxInitializer(
			Settings.RegisterProxySetting(
				page,
				"ShortestPathForever_arrowMove",
				Settings.VarType.Boolean,
				L["Move the arrow"],
				false,
				ns.ArrowMoving,
				ns.MoveArrow
			),
			nil,
			L["Shows the arrow to drag anywhere; Shift-drag or the arrow keys nudge it. Right-click it to put it back."]
		)
	)
	local arrowScale = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_arrowScale",
		"arrowScale",
		ns.db,
		Settings.VarType.Number,
		L["Arrow scale"],
		ns.Defaults.arrowScale
	)
	arrowScale:SetValueChangedCallback(function(_, value)
		if type(value) == "number" then
			ns.SetArrowScale(value)
		end
	end)
	settings.arrowScale = arrowScale
	local arrowOptions = Settings.CreateSliderOptions(50, 200, 10)
	arrowOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return value .. "%"
	end)
	Settings.RegisterInitializer(
		page,
		Settings.CreateSliderInitializer(arrowScale, arrowOptions, L["Scales the arrow and the cast prompt."])
	)
	local arrowLabel = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_arrowLabel",
		"arrowLabel",
		ns.db,
		Settings.VarType.String,
		L["Arrow label"],
		ns.Defaults.arrowLabel
	)
	arrowLabel:SetValueChangedCallback(function(_, value)
		if type(value) == "string" then
			ns.SetArrowLabel(value)
		end
	end)
	settings.arrowLabel = arrowLabel
	local arrowLabelOptions = Settings.CreateControlTextContainer()
	arrowLabelOptions:Add("distance", L["Distance"])
	arrowLabelOptions:Add("time", L["Time left"])
	arrowLabelOptions:Add("both", L["Both"])
	Settings.RegisterInitializer(
		page,
		Settings.CreateDropdownInitializer(arrowLabel, function()
			return arrowLabelOptions:GetData()
		end, L["What the direction arrow shows under it: the distance to walk, the time left in the journey, or both."])
	)
	Checkbox(
		"arrowObjectives",
		L["Objectives under the arrow"],
		L["The stop's live objectives under the arrow while it leads."]
			.. " "
			.. L["The pin shown when you reach a stop keeps its own lines."],
		ns.ArrowObjectivesChanged
	)
	Checkbox(
		"metres",
		L["Distances in metres"],
		L["Label distances in metres, as the game's metric-language clients do. The numbers stay the game's own."],
		function()
			ns.RefreshCompass()
			ns.RefreshTracker()
			ns.WakeTravel()
		end
	)
	Checkbox(
		"minimapButton",
		L["Show options button on minimap"],
		L["Open these settings from the minimap."],
		ns.RefreshOptionsButton
	)
	Checkbox(
		"compass",
		L["Show the compass"],
		L["While Guide is on: your next turns, the next stop and your destination across the top of the screen."],
		ns.RefreshCompass
	)
	Checkbox(
		"compassTime",
		L["Show the time left under the compass"],
		L["The journey's time left, as the tracker shows it, beside the distance to your next turn."],
		ns.RefreshCompass
	)
	Settings.RegisterInitializer(
		page,
		Settings.CreateCheckboxInitializer(
			Settings.RegisterProxySetting(
				page,
				"ShortestPathForever_compassMove",
				Settings.VarType.Boolean,
				L["Move the compass"],
				false,
				ns.CompassMoving,
				ns.MoveCompass
			),
			nil,
			L["Shows the compass to drag anywhere; Shift-drag or the arrow keys nudge it. Right-click it to put it back."]
		)
	)
	if host and host.GetScale and host.SetScale then
		local scale = Settings.RegisterProxySetting(
			page,
			"ShortestPathForever_trackerScale",
			Settings.VarType.Number,
			L["Tracker scale"],
			100,
			function()
				return math.floor(host.GetScale() * 100 + 0.5)
			end,
			function(value)
				host.SetScale(value / 100)
			end
		)
		local scaleOptions = Settings.CreateSliderOptions(50, 200, 10)
		scaleOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return value .. "%"
		end)
		Settings.RegisterInitializer(
			page,
			Settings.CreateSliderInitializer(
				scale,
				scaleOptions,
				L["Scales the shared Forever tracker. 100% matches the game's own tracker."]
			)
		)
	end
	local compassScale = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_compassScale",
		"compassScale",
		ns.db,
		Settings.VarType.Number,
		L["Compass scale"],
		ns.Defaults.compassScale
	)
	compassScale:SetValueChangedCallback(function(_, value)
		if type(value) == "number" then
			ns.SetCompassScale(value)
		end
	end)
	settings.compassScale = compassScale
	local compassOptions = Settings.CreateSliderOptions(50, 200, 10)
	compassOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return value .. "%"
	end)
	Settings.RegisterInitializer(
		page,
		Settings.CreateSliderInitializer(
			compassScale,
			compassOptions,
			L["Scales the compass. 100% matches the game's own art."]
		)
	)
	local compassBackground = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_compassBackground",
		"compassBackground",
		ns.db,
		Settings.VarType.Number,
		L["Compass background"],
		ns.Defaults.compassBackground
	)
	compassBackground:SetValueChangedCallback(function(_, value)
		if type(value) == "number" then
			ns.SetCompassBackground(value)
		end
	end)
	settings.compassBackground = compassBackground
	local backgroundOptions = Settings.CreateSliderOptions(0, 80, 10)
	backgroundOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return value .. "%"
	end)
	Settings.RegisterInitializer(
		page,
		Settings.CreateSliderInitializer(
			compassBackground,
			backgroundOptions,
			L["Darkens the ground behind the compass so its marks stay readable on snow or sand. 0% shows none."]
		)
	)
	Checkbox(
		"whatsNew",
		L["What's new after an update"],
		L["One line in chat the first time you log in after an update."]
	)

	-- The Forever addons page is ForeverCore's, with the hint setting on it.
	-- With the gamepad interface on the page is the client's own rows so the Options navigation can enter it
	-- (cjber/tweaks-forever#382).
	local family = ForeverCore.Family.Register(category, ns.db, addonName, ns.core.SafeCall)
	Settings.RegisterInitializer(
		category,
		CreateSettingsButtonInitializer(L["Forever addons"], L["Open"], function()
			ForeverCore.OpenSettingsPanel(family:GetID())
		end, nil, false)
	)

	Settings.RegisterAddOnCategory(category)
	ns.RefreshOptionsButton()
	SLASH_SHORTESTPATHFOREVER1 = "/path"
	SLASH_SHORTESTPATHFOREVER2 = "/shortestpath"
	SlashCmdList.SHORTESTPATHFOREVER = function(message)
		-- TomTom's /way line, which works whether or not /way itself is free.
		if ns.core.Report.Command(message) then
			return
		end
		local way = message == "way" and "" or message:match("^way%s+(.*)$")
		if way then
			ns.Way(way)
			return
		elseif message:match("^follow") then
			local unit = message:match("^follow%s*(.*)$")
			if unit == "" or unit == nil then
				-- The first party member is who a follow is nearly always for.
				unit = "party1"
			end
			if unit == "off" or ns.IsFollowing() and unit == "" then
				ns.StopFollowing()
				ns.Print(L["No longer following."])
				return
			end
			if ns.StartFollowing(unit) then
				ns.Print(L["Following %s."]:format(L["Party member"]))
			end
			return
		elseif message:match("^menutest") then
			local value = message:match("^menutest%s+(%S+)")
			if value and ns.SetMenuTest(value) then
				ns.Print(L["World map filter menu test: %s. Type /reload to apply."]:format(value))
			else
				ns.Print(L["Usage: /path menutest map, nearby, both or off"])
			end
			return
		elseif message == "perf" then
			Perf()
			return
		elseif message == "stats" then
			local stats = ns.TravelStats()
			if not stats then
				ns.Print(L["Travel stats are not ready yet."])
				return
			end
			ns.Print(
				string.format(
					L["Local travel journal — approx. %d yd walked; %d journeys; %d transports; %d flights; %d portal legs."],
					stats.walkedYards,
					stats.routesCompleted,
					stats.transportsUsed,
					stats.flightsTaken,
					stats.portalsUsed
				)
			)
			return
		elseif message:match("^leaderboard") then
			ns.OpenTravelLeaderboard()
			return
		elseif message == "help" then
			ns.Print(L["/path report - show a report to copy into a bug report"])
			ns.Print(L["/path issue - report a bug or request a feature with a ready-made GitHub issue link"])
			return
		elseif message == "debug" then
			ns.db.debug = not ns.db.debug
			ns.db.trace = ns.db.debug and {} or nil
			ns.WakeTravel()
			ns.Print("debug " .. (ns.db.debug and "on" or "off"))
			return
		end
		ns.OpenSettings()
	end
	ShortestPathForever_OnAddonCompartmentClick = function()
		ns.OpenSettings()
	end
end)
