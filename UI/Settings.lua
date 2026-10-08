local addonName = ...
---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

local settings = {}

-- Change an option from anywhere (the map's filter menu) with the settings panel kept in step.
---@param key string
---@param value boolean|number
function ns.SetOption(key, value)
	settings[key]:SetValue(value)
end

local category

-- The settings category is the addon's one options surface: the slash command and the compartment entry open it.
function ns.OpenSettings()
	Settings.OpenToCategory(category:GetID())
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
				Settings.OpenToCategory(subcategory:GetID())
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
		L["Show the next departures"],
		L["In the objective tracker while you are near a dock, lift or tram."],
		ns.RefreshTracker
	)
	Checkbox(
		"share",
		L["Share departure times"],
		L["Sends and receives sighting times over guild, party and at the dock. No chat messages are shown."]
	)

	-- Guidance: how a journey is planned and led.
	Page(L["Guidance"])
	local host = ns.TrackerHost
	if host and host.GetSettings and host.SetAttached and host.OnAttachmentChanged then
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
	end
	Checkbox(
		"journey",
		L["Shift-click to plan journeys"],
		L["Shift-click the world map or the minimap to plan a journey there."],
		function()
			if not ns.db.journey then
				ns.ClearJourney()
			end
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
		"restedxp",
		L["Follow RestedXP guides"],
		L["Plan journeys to RestedXP guide targets and hide its arrow. No TomTom needed."],
		function()
			ns.RefreshRestedXP()
		end
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

	-- Alerts: the arrival warning.
	Page(L["Alerts"])
	Checkbox(
		"alerts",
		L["Alert before a boat arrives"],
		L["While you wait at a dock or ride a timed boat: a warning on screen and a flashing taskbar icon."]
	)
	Checkbox("alertSound", L["Play a sound with alerts"], L["Plays even with the game in the background."])

	-- Interface: what the addon puts on screen.
	Page(L["Interface"])
	Checkbox(
		"compass",
		L["Show the compass"],
		L["While Guide is on: your next turns, the next stop and your destination across the top of the screen."],
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
			L["Shows the compass so you can drag it anywhere on screen. Right-click it to put it back."]
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
	Checkbox(
		"whatsNew",
		L["What's new after an update"],
		L["One line in chat the first time you log in after an update."]
	)

	Settings.RegisterAddOnCategory(category)
	SLASH_SHORTESTPATHFOREVER1 = "/path"
	SLASH_SHORTESTPATHFOREVER2 = "/shortestpath"
	SlashCmdList.SHORTESTPATHFOREVER = function(message)
		if message == "perf" then
			Perf()
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
