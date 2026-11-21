local addonName = ...
---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- Native initializers and their options must be produced in secure execution. The list reads them while
-- constructing shared gamepad binding footers, including rows beside the selected one.
local delegates = {}
local function Secure(fn)
	-- A client without CreateSecureDelegate (UI/Canvas.lua guards it too) gets the plain initializers.
	if type(CreateSecureDelegate) ~= "function" then
		return fn
	end
	if not delegates[fn] then
		delegates[fn] = CreateSecureDelegate(fn)
	end
	return delegates[fn]
end

-- Blizzard calls slider formatters directly. A native closure isolates our formatting callback so its taint
-- cannot escape into the rest of the native row initialization or the shared binding stack.
local function Label(options, callback)
	local formatter = Secure(GenerateClosure)(securecallfunction, callback)
	Secure(options.SetLabelFormatter)(options, MinimalSliderWithSteppersMixin.Label.Right, formatter)
end
local settings = {}

-- Change an option from anywhere and keep the settings panel in step.
---@param key string
---@param value boolean|number|string
function ns.SetOption(key, value)
	local setting = settings[key]
	if setting then
		setting:SetValue(value)
	else
		ns.db[key] = value
	end
end
local category

-- The settings category is opened through ForeverCore's secure opener.
function ns.OpenSettings()
	ForeverCore.OpenSettingsPanel(category:GetID())
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
			Secure(CreateSettingsButtonInitializer)(name, L["Open"], function()
				ForeverCore.OpenSettingsPanel(subcategory:GetID())
			end, nil, false)
		)
	end
	local function Section(name)
		local sections = ForeverCore and ForeverCore.SettingsSections
		if sections and sections.Register then
			sections.Register(page, name)
		end
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
		Settings.RegisterInitializer(page, Secure(Settings.CreateCheckboxInitializer)(setting, nil, tooltip))
		settings[key] = setting
	end
	local function Scale(key, name, tooltip, refresh, minimum, step)
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
		local options = Secure(Settings.CreateSliderOptions)(minimum or 25, 200, step or 5)
		Label(options, function(value)
			return value .. "%"
		end)
		Settings.RegisterInitializer(page, Secure(Settings.CreateSliderInitializer)(setting, options, tooltip))
	end
	-- A dropdown over a fixed list of choices: a saved string, one row of labels, and the choice's own key handed
	-- back to onChanged.
	local function Dropdown(key, name, tooltip, choices, onChanged)
		local setting = Settings.RegisterAddOnSetting(
			page,
			"ShortestPathForever_" .. key,
			key,
			ns.db,
			Settings.VarType.String,
			name,
			ns.Defaults[key]
		)
		if onChanged then
			setting:SetValueChangedCallback(onChanged)
		end
		settings[key] = setting
		local options = Secure(Settings.CreateControlTextContainer)()
		for _, choice in ipairs(choices) do
			Secure(options.Add)(options, choice.key, choice.label)
		end
		Settings.RegisterInitializer(
			page,
			Secure(Settings.CreateDropdownInitializer)(
				setting,
				Secure(GenerateClosure)(options.GetData, options),
				tooltip
			)
		)
	end
	-- A minimum time a teleport must save, in seconds; 0 is off.
	local function Saving(key, name, tooltip)
		local setting = Settings.RegisterAddOnSetting(
			page,
			"ShortestPathForever_" .. key,
			key,
			ns.db,
			Settings.VarType.Number,
			name,
			ns.Defaults[key]
		)
		setting:SetValueChangedCallback(ns.TravelPolicyChanged)
		settings[key] = setting
		local options = Secure(Settings.CreateSliderOptions)(0, 600, 30)
		Label(options, function(value)
			return value > 0 and SecondsToTime(value) or OFF
		end)
		Settings.RegisterInitializer(page, Secure(Settings.CreateSliderInitializer)(setting, options, tooltip))
	end

	-- Each page is its own module: UI/SettingsMapMarks.lua opens the Map marks page and adds its rows through these
	-- builders, so every row registers through the same secure initializer and ns.SetOption finds it.
	---@type SPFSettingsRows
	local rows = { Page = Page, Section = Section, Checkbox = Checkbox, Scale = Scale, Dropdown = Dropdown }
	-- Guidance: how a journey is planned and led.
	Page(L["Guidance"])
	Section(L["Tracker"])
	Checkbox(
		"journeyTracker",
		L["Show the journey tracker"],
		L["Off keeps the arrow, pin, map line and minimap route, with no journey block in the tracker."],
		ns.RefreshTracker
	)
	Checkbox(
		"tracker",
		L["Show boat, lift and tram departures in the tracker"],
		L["In the tracker while you are near a dock, lift or tram."],
		ns.RefreshTracker
	)
	local host = ForeverCore.TrackerHost --[[@as ForeverTrackerHostAPI]]
	-- The shared column's attach choice, the same row and words in every Forever addon (forever-core#910). It sits by
	-- the scale and lock, the other rows that place the shared tracker.
	local sections = ForeverCore.SettingsSections
	if sections and sections.RegisterTrackerAttach then
		sections.RegisterTrackerAttach(page, "ShortestPathForever_trackerAttached")
	end
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
		Secure(Settings.CreateCheckboxInitializer)(
			lock,
			nil,
			L["Keeps the shared Forever tracker where you put it. The grip at its top no longer drags it."]
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
		local scaleOptions = Secure(Settings.CreateSliderOptions)(50, 200, 10)
		Label(scaleOptions, function(value)
			return value .. "%"
		end)
		Settings.RegisterInitializer(
			page,
			Secure(Settings.CreateSliderInitializer)(
				scale,
				scaleOptions,
				L["Scales the shared Forever tracker. 100% matches the game's own tracker."]
			)
		)
	end
	local trackerHeight = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_trackerHeight",
		"trackerHeight",
		ns.db,
		Settings.VarType.Number,
		L["Journey tracker height"],
		(ns.Defaults --[[@as any]]).trackerHeight
	)
	trackerHeight:SetValueChangedCallback(function(_, value)
		local db = ns.db --[[@as any]]
		db.trackerHeight = value
		ns.SetTrackerHeight(value)
	end)
	local trackerHeightOptions = Secure(Settings.CreateSliderOptions)(100, 400, 20)
	Label(trackerHeightOptions, function(value)
		return value .. " UI units"
	end)
	Settings.RegisterInitializer(
		page,
		Secure(Settings.CreateSliderInitializer)(
			trackerHeight,
			trackerHeightOptions,
			L["Limits the Journey section to this height; longer journeys scroll inside it."]
		)
	)
	Checkbox(
		"resumeJourney",
		L["Keep journeys after a reload"],
		L["Your own journey starts again after a /reload, or logging back in within 30 minutes. Guides start theirs."],
		function()
			ns.KeepJourneyChanged()
		end
	)
	Section(L["Planning"])
	Checkbox(
		"journey",
		L["Enable journeys"],
		L["Off clears your journey, and map clicks, quests, guides and waypoints no longer start one."],
		function()
			if not ns.db.journey then
				ns.ClearJourney()
			end
			-- The guide follower only ticks while journeys are on; turning them back on starts it again.
			ns.RefreshGuidelime()
		end
	)
	local journeyKey = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_journeyKey",
		"journeyKey",
		ns.db,
		Settings.VarType.String,
		L["Key to plan a journey"],
		ns.Defaults.journeyKey
	)
	settings.journeyKey = journeyKey
	local journeyKeyOptions = Secure(Settings.CreateControlTextContainer)()
	for _, key in ipairs(ns.JourneyKeys) do
		Secure(journeyKeyOptions.Add)(journeyKeyOptions, key, ns.JourneyKeyName(key))
	end
	Settings.RegisterInitializer(
		page,
		Secure(Settings.CreateDropdownInitializer)(
			journeyKey,
			Secure(GenerateClosure)(journeyKeyOptions.GetData, journeyKeyOptions),
			L["The key you hold to plan a journey from the world map or the minimap."]
				.. " "
				.. L["Over a Questie icon, Shift-click stays Questie's; Alt-click plans the journey there with either key."]
		)
	)
	Checkbox(
		"journeyHint",
		L["Show the journey key hint in tooltips"],
		-- luacheck: push ignore 631
		L["Adds a line naming your journey key to tooltips on the world map, flight points and the minimap. Off, the key still plans journeys."]
		-- luacheck: pop
	)
	Checkbox(
		"focusedQuest",
		L["Route to the focused quest"],
		-- luacheck: push ignore 631
		L["Starts a journey when you super-track a quest or place the game's map pin, so a controller needs no map click. A guide addon's own journey is left alone."]
		-- luacheck: pop
	)
	Section(L["Destination"])
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
	local destinationPinSize = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_destinationPinSize",
		"destinationPinSize",
		ns.db,
		Settings.VarType.Number,
		L["Destination pin size"],
		ns.Defaults.destinationPinSize
	)
	destinationPinSize:SetValueChangedCallback(function(_, value)
		if type(value) == "number" then
			ns.RefreshDestinationPinSize()
		end
	end)
	settings.destinationPinSize = destinationPinSize
	local destinationPinOptions = Secure(Settings.CreateSliderOptions)(50, 100, 5)
	Label(destinationPinOptions, function(value)
		return value .. "%"
	end)
	Settings.RegisterInitializer(
		page,
		Secure(Settings.CreateSliderInitializer)(
			destinationPinSize,
			destinationPinOptions,
			L["Scales the pin over the destination on the world map."]
		)
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
	local arrivalOptions = Secure(Settings.CreateSliderOptions)(5, 50, 5)
	Label(arrivalOptions, function(value)
		return ns.FormatDistance(value)
	end)
	Settings.RegisterInitializer(
		page,
		Secure(Settings.CreateSliderInitializer)(
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
	Section(L["Guides"])
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
		"dugi",
		L["Follow Dugi guides"],
		L["Plan journeys to Dugi's current guide step. Dugi keeps its own arrow."],
		function()
			ns.RefreshDugi()
		end
	)
	Settings.RegisterInitializer(
		page,
		Secure(CreateSettingsButtonInitializer)(L["RestedXP guide"], L["Resume guide"], function()
			ns.ResumeRestedXP()
		end, nil, false)
	)
	Settings.RegisterInitializer(
		page,
		Secure(CreateSettingsButtonInitializer)(L["Guidelime"], L["Resume guide"], function()
			ns.ResumeGuidelime()
		end, nil, false)
	)
	Settings.RegisterInitializer(
		page,
		Secure(CreateSettingsButtonInitializer)(L["Dugi Guides"], L["Resume guide"], function()
			ns.ResumeDugi()
		end, nil, false)
	)

	Section(L["Route choices"])
	Checkbox(
		"avoidHighZones",
		L["Avoid zones far above my level"],
		L["Walk less in zones with a minimum level 4 or more above yours, even at your destination."],
		ns.TravelPolicyChanged
	)
	Checkbox(
		"followRoads",
		L["Follow roads"],
		L["Prefer roads and paved streets. Roads painted with a zone's plain dirt are not known."],
		ns.TravelPolicyChanged
	)
	local roadDetour = Settings.RegisterAddOnSetting(
		page,
		"ShortestPathForever_roadDetour",
		"roadDetour",
		ns.db,
		Settings.VarType.Number,
		L["Road detour allowance"],
		ns.Defaults.roadDetour
	)
	roadDetour:SetValueChangedCallback(ns.TravelPolicyChanged)
	settings.roadDetour = roadDetour
	local roadOptions = Secure(Settings.CreateSliderOptions)(0, ns.Hazards.ROAD_DETOUR_MAX, 25)
	Label(roadOptions, function(value)
		return value .. "%"
	end)
	Settings.RegisterInitializer(
		page,
		Secure(Settings.CreateSliderInitializer)(
			roadDetour,
			roadOptions,
			-- luacheck: push ignore 631
			L["With Follow roads on, how much extra distance is worth taking to avoid the same distance off-road. 50% keeps the usual preference; 0% gives no road preference. This is not a limit on the whole walk."]
			-- luacheck: pop
		)
	)
	Checkbox(
		"useWaterWalking",
		L["Use Water Walking and Levitate"],
		L["Use Water Walking or Levitate when available. When off, routes use swimming times and may still cross water."],
		ns.TravelPolicyChanged
	)
	Checkbox(
		"useHearthstone",
		L["Use Hearthstone"],
		-- luacheck: push ignore 631
		L["Journeys can start with your Hearthstone or Astral Recall. Turn it off to save it for later; class teleports are still offered."],
		-- luacheck: pop
		function(_, value)
			ns.SetHearthstoneEnabled(type(value) == "boolean" and value or (ns.db.useHearthstone == true))
		end
	)
	Saving(
		"hearthMinimumSavings",
		L["Minimum Hearthstone saving"],
		L["Only use the Hearthstone when it saves at least this much time."]
	)
	Checkbox(
		"teleports",
		L["Use class teleports"],
		-- luacheck: push ignore 631
		L["Journeys, and other addons' estimates from here, can start with a mage's city teleport or Teleport: Moonglade, cooldown counted."],
		-- luacheck: pop
		ns.TravelPolicyChanged
	)
	Saving(
		"teleportMinimumSavings",
		L["Minimum teleport saving"],
		L["Only use a class teleport when it saves at least this much time."]
	)
	Section(L["Map"])
	Checkbox(
		"guideStops",
		L["Mark only where steps end"],
		L["Guide marks where each step ends on the map, not each turn of the walk. Arrow bearing is set separately."],
		ns.GuideStopsChanged
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

	ns.SettingsMapMarks.Register(rows)

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
	Section(L["Direction arrow"])
	Checkbox(
		"arrow",
		L["Show direction arrow"],
		L["Show the next direction and the game's navigation marker."],
		function()
			ns.JourneyGuide.ArrowChanged()
			ns.WakeTravel()
		end
	)
	Settings.RegisterInitializer(
		page,
		Secure(Settings.CreateCheckboxInitializer)(
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
	Checkbox(
		"castPrompt",
		L["Show cast prompt"],
		-- luacheck: push ignore 631
		L["Shows the Hearthstone or teleport to use in the arrow's place. Off, journeys still use them and the tracker still names the step."],
		-- luacheck: pop
		function()
			ns.JourneyGuide.ArrowChanged()
		end
	)
	Scale("arrowScale", L["Arrow scale"], L["Scales the arrow and the cast prompt."], function(_, value)
		if type(value) == "number" then
			ns.SetArrowScale(value)
		end
	end, 50, 10)
	-- stylua: ignore
	Checkbox(
		"arrowDirect",
		L["Point straight to the destination"],
		L["The game's navigation marker points straight to the destination, or to the current travel step on another map; the arrow does the same when that marker is off. Map marks and journey time keep following the route."], -- luacheck: ignore 631
		ns.ArrowBearingChanged
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
	local arrowLabelOptions = Secure(Settings.CreateControlTextContainer)()
	Secure(arrowLabelOptions.Add)(arrowLabelOptions, "distance", L["Distance"])
	Secure(arrowLabelOptions.Add)(arrowLabelOptions, "time", L["Time left"])
	Secure(arrowLabelOptions.Add)(arrowLabelOptions, "both", L["Both"])
	-- stylua: ignore
	Settings.RegisterInitializer(
		page,
		Secure(Settings.CreateDropdownInitializer)(arrowLabel, Secure(GenerateClosure)(arrowLabelOptions.GetData, arrowLabelOptions), L["What the direction arrow shows under it: the distance in the selected arrow mode, the time left in the journey, or both."]) -- luacheck: ignore 631
	)
	Checkbox(
		"arrowObjectives",
		L["Objectives under the arrow"],
		L["The stop's live objectives under the arrow while it leads."]
			.. " "
			.. L["The pin shown when you reach a stop keeps its own lines."],
		ns.ArrowObjectivesChanged
	)
	Section(L["Compass"])
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
		Secure(Settings.CreateCheckboxInitializer)(
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
	local compassOptions = Secure(Settings.CreateSliderOptions)(50, 200, 10)
	Label(compassOptions, function(value)
		return value .. "%"
	end)
	Settings.RegisterInitializer(
		page,
		Secure(Settings.CreateSliderInitializer)(
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
	local backgroundOptions = Secure(Settings.CreateSliderOptions)(0, 80, 10)
	Label(backgroundOptions, function(value)
		return value .. "%"
	end)
	Settings.RegisterInitializer(
		page,
		Secure(Settings.CreateSliderInitializer)(
			compassBackground,
			backgroundOptions,
			L["Darkens the ground behind the compass so its marks stay readable on snow or sand. 0% shows none."]
		)
	)
	Section(L["General"])
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
		"stats",
		L["Record travel stats"],
		L["On by default. Records approximate walking distance, completed journeys and transport use."]
	)
	Checkbox(
		"whatsNew",
		L["What's new after an update"],
		L["One line in chat the first time you log in after an update."]
	)

	Settings.RegisterAddOnCategory(category)
	SLASH_SHORTESTPATHFOREVER1 = "/path"
	SLASH_SHORTESTPATHFOREVER2 = "/shortestpath"
	SlashCmdList.SHORTESTPATHFOREVER = function(message)
		-- TomTom's /way line, which works whether or not /way itself is free.
		if ns.core.Report.Command(message) then
			return
		end
		if message == "stops" then
			ns.ShowJourneyStops()
			return
		end
		if message == "farm" then
			ns.OpenFarming()
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
		elseif message == "help" then
			ns.Print(L["/path farm - choose recorded gathering locations"])
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
