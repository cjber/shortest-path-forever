-- Settings rows must reach their layout only through Settings.RegisterInitializer, which inserts them from
-- Blizzard's secure attribute delegate. Settings.CreateCheckbox inserts from the caller instead, which taints
-- the settings search, and a restricted button in its results (Social's Discord Sign In) is then blocked and
-- blamed on this addon. The index buttons go through RegisterInitializer too, and keep themselves out of search.
local rows, buttons, settings = {}, {}, {}
local opened = {}
local familyPage

local attachmentNotified, attachmentChanged
local trackerState = { attached = true }
local trackerScale, compassScaled, compassBackdrop = 1, nil, nil
local sharingChanges, leaderboardOpened = 0, nil
local env = setmetatable({
	MinimalSliderWithSteppersMixin = { Label = { Right = 1 } },
	OFF = "Off",
	SecondsToTime = function(seconds)
		return seconds .. " Sec"
	end,
	Settings = {
		RegisterProxySetting = function(category, variable, varType, name, default, get, set)
			local setting = {
				category = category,
				variable = variable,
				key = variable:match("_(%a+)$"),
				varType = varType,
				name = name,
				default = default,
				GetValue = get,
				SetValue = function(_, value)
					set(value)
				end,
			}
			settings[#settings + 1] = setting
			return setting
		end,
		NotifyUpdate = function(variable)
			attachmentNotified = variable
		end,
		VarType = { Boolean = "boolean", Number = "number", String = "string" },
		RegisterVerticalLayoutCategory = function(name)
			return {
				name = name,
				GetID = function(self)
					return self.name
				end,
			}, {
				AddInitializer = function()
					error("addon code inserted a row into a settings layout; use Settings.RegisterInitializer")
				end,
			}
		end,
		RegisterCanvasLayoutSubcategory = function()
			error("the Forever addons page registers with ForeverCore.Family.Register, not a canvas")
		end,
		RegisterVerticalLayoutSubcategory = function(parent, name)
			return {
				name = name,
				parent = parent,
				GetID = function(self)
					return self.name
				end,
			}
		end,
		RegisterAddOnSetting = function(category, variable, key, _, varType, name, default)
			local setting = {
				category = category,
				variable = variable,
				key = key,
				varType = varType,
				name = name,
				default = default,
			}
			function setting:SetValueChangedCallback(callback)
				self.onChanged = callback
			end
			settings[#settings + 1] = setting
			return setting
		end,
		CreateCheckbox = function()
			error("Settings.CreateCheckbox inserts from addon code; use Settings.RegisterInitializer")
		end,
		CreateCheckboxInitializer = function(setting, options, tooltip)
			assert(setting.varType == "boolean" and options == nil)
			return { kind = "checkbox", setting = setting, tooltip = tooltip }
		end,
		CreateSliderOptions = function(minimum, maximum, step)
			return {
				minValue = minimum,
				maxValue = maximum,
				step = step,
				SetLabelFormatter = function(self, _, format)
					self.format = format
				end,
			}
		end,
		CreateSliderInitializer = function(setting, options, tooltip)
			assert(setting.varType == "number" and options)
			return { kind = "slider", setting = setting, options = options, tooltip = tooltip }
		end,
		CreateControlTextContainer = function()
			local data = {}
			return {
				Add = function(_, value, text)
					data[#data + 1] = { value = value, text = text }
				end,
				GetData = function()
					return data
				end,
			}
		end,
		CreateDropdownInitializer = function(setting, getData, tooltip)
			assert(setting.varType == "string" and type(getData) == "function")
			return { kind = "dropdown", setting = setting, getData = getData, tooltip = tooltip }
		end,
		RegisterInitializer = function(target, initializer)
			if initializer.kind == "button" then
				if target.name == "Shortest Path Forever" then
					buttons[#buttons + 1] = { target = target, initializer = initializer }
				end
			else
				assert(initializer.setting.category == target, "a row sits on the page Blizzard is told about")
				rows[#rows + 1] = { target = target, initializer = initializer }
			end
		end,
		RegisterAddOnCategory = function(target)
			assert(target.name == "Shortest Path Forever", "the index page is the addon's category")
			assert(#rows == #settings, "every row registers before the category")
		end,
		OpenToCategory = function()
			error("Blizzard's Settings.OpenToCategory is restricted: open settings through ForeverCore (#333)")
		end,
	},
	CreateSettingsButtonInitializer = function(name, description, callback, tags, addSearchTags)
		assert(tags == nil and addSearchTags == false, "index buttons stay out of the settings search")
		return { kind = "button", name = name, description = description, callback = callback }
	end,
	SlashCmdList = {},
}, { __index = _G })
-- ForeverCore's secure settings opener runs the client's restricted C_SettingsUtil.OpenSettingsPanel through
-- CreateSecureDelegate, and records what it opened.
local secureCalls = 0
env.InCombatLockdown = function()
	return false
end
env.CreateSecureDelegate = function(fn)
	return function(...)
		secureCalls = secureCalls + 1
		return fn(...)
	end
end
env.C_SettingsUtil = {
	OpenSettingsPanel = function(categoryID)
		opened[#opened + 1] = categoryID
	end,
}
local ForeverCore = dofile("tests/forever_core.lua")
local coreNs = ForeverCore.load(env, "ForeverCore", { "Locales/enUS.lua", "Core/OpenSettings.lua" })
env.ForeverCore = {
	OpenSettingsPanel = coreNs.OpenSettingsPanel,
	Family = {
		Register = function(category, db, current, safeCall)
			familyPage = { category = category, db = db, current = current, safeCall = safeCall }
			return {
				GetID = function()
					return "Forever addons"
				end,
			}
		end,
	},
}

local refreshed, taxiRefreshed, policyChanged, tomtomRefreshed, guidelimeRefreshed = 0, 0, 0, 0, 0
local trackerRefreshed = 0
local compassMoving = false
local arrowMoving, arrowScaled, arrowLabelSet = false, nil, nil
local arrowObjectivesChanged = 0
local tomtomFollowRefreshed, ways = 0, {}
local routeColour = nil
local routeLinesRefreshed = 0
-- Core/Core.lua's defaults: every row on.
local ns = {
	core = {
		SafeCall = function(_, fn, ...)
			return pcall(fn, ...)
		end,
	},
	TrackerHost = {
		GetSettings = function()
			return trackerState
		end,
		SetAttached = function(value)
			trackerState.attached = value
			attachmentChanged()
		end,
		OnAttachmentChanged = function(callback)
			attachmentChanged = callback
		end,
		SetLocked = function(value)
			trackerState.locked = value
		end,
		GetScale = function()
			return trackerScale
		end,
		SetScale = function(value)
			trackerScale = value
		end,
	},
	TravelPolicyChanged = function()
		policyChanged = policyChanged + 1
	end,
	RefreshRestedXP = function() end,
	RefreshTracker = function()
		trackerRefreshed = trackerRefreshed + 1
	end,
	RefreshGuidelime = function()
		guidelimeRefreshed = guidelimeRefreshed + 1
	end,
	RefreshTomTom = function()
		tomtomRefreshed = tomtomRefreshed + 1
	end,
	RefreshTomTomFollow = function()
		tomtomFollowRefreshed = tomtomFollowRefreshed + 1
	end,
	Way = function(message)
		ways[#ways + 1] = message
	end,
	Family = {
		Register = function(category, db, current, locale)
			familyPage = { category = category, db = db, current = current, locale = locale }
			return {
				name = "Forever addons",
				GetID = function(self)
					return self.name
				end,
			}
		end,
	},
	TravelSharingChanged = function()
		sharingChanges = sharingChanges + 1
	end,
	OpenTravelLeaderboard = function()
		leaderboardOpened = true
	end,
	db = {},
	Defaults = setmetatable({
		-- Travel participation defaults are explicit, matching Core/Core.lua.
		stats = true,
		statsShare = true,
		partyMagePortals = false,
		hearthMinimumSavings = 0,
		compassScale = 100,
		arrowScale = 100,
		arrowLabel = "distance",
		compassBackground = 0,
		tomtomFollow = false,
		compassTime = false,
		arrivalSound = false,
		resumeJourney = false,
		routeColor = "gold",
		followRoads = false,
		arrivalDistance = 15,
	}, {
		__index = function()
			return true
		end,
	}),
	Init = function(fn)
		fn()
	end,
	RefreshMap = function()
		refreshed = refreshed + 1
	end,
	RefreshTaxiRoute = function()
		taxiRefreshed = taxiRefreshed + 1
	end,
	CompassMoving = function()
		return compassMoving
	end,
	MoveCompass = function(value)
		compassMoving = value
	end,
	SetCompassScale = function(value)
		compassScaled = value
	end,
	ArrowMoving = function()
		return arrowMoving
	end,
	MoveArrow = function(value)
		arrowMoving = value
	end,
	SetArrowScale = function(value)
		arrowScaled = value
	end,
	SetArrowLabel = function(value)
		arrowLabelSet = value
	end,
	ArrowObjectivesChanged = function()
		arrowObjectivesChanged = arrowObjectivesChanged + 1
	end,
	SetCompassBackground = function(value)
		compassBackdrop = value
	end,
	FormatDistance = function(yards)
		return yards .. " yd"
	end,
	SetRouteColor = function(value)
		routeColour = value
	end,
	RefreshRouteLines = function()
		routeLinesRefreshed = routeLinesRefreshed + 1
	end,
	RouteColors = {
		{ key = "gold", label = "Gold" },
		{ key = "white", label = "White" },
		{ key = "cyan", label = "Cyan" },
		{ key = "green", label = "Green" },
		{ key = "magenta", label = "Magenta" },
	},
}
env.ForeverCore.TrackerHost = ns.TrackerHost
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
setfenv(assert(loadfile("UI/Settings.lua")), env)("ShortestPathForever", ns)

-- The index page is one button per group; each opens that group's page. The groups divide the old flat list, and
-- every row keeps its key, default, tooltip and callback.
local groups = {
	["Map marks"] = {
		"pins",
		"transit",
		"portals",
		"mapFlightMasters",
		"minimapPins",
		"mapPinScale",
		"flightPinScale",
		"minimapPinScale",
		"routeColor",
		"mapLine",
		"minimapLine",
	},
	Transport = { "mapRoutes", "otherFaction", "tracker", "share" },
	["Travel journal"] = { "stats", "statsShare" },
	Guidance = {
		"trackerAttached",
		"trackerLocked",
		"journey",
		"journeyTracker",
		"resumeJourney",
		"destinationPin",
		"arrivalPin",
		"arrivalDistance",
		"npcArrows",
		"tomtom",
		"tomtomFollow",
		"restedxp",
		"restedxpHideArrow",
		"guidelime",
		"avoidHighZones",
		"followRoads",
		"teleports",
		"hearthMinimumSavings",
		"guideStops",
		"taxiRoute",
		"corpse",
	},
	["Party mage portals"] = {
		"partyMagePortals",
		"partyMageStormwind",
		"partyMageIronforge",
		"partyMageDarnassus",
		"partyMageUndercity",
		"partyMageThunderBluff",
		"partyMageOrgrimmar",
	},
	Alerts = { "alerts", "flightPathReminder", "alertSound", "arrivalSound" },
	Interface = {
		"arrow",
		"arrowMove",
		"arrowScale",
		"arrowLabel",
		"arrowObjectives",
		"metres",
		"minimapButton",
		"compass",
		"compassTime",
		"compassMove",
		"trackerScale",
		"compassScale",
		"compassBackground",
		"whatsNew",
	},
}
local order = {
	"Map marks",
	"Transport",
	"Travel journal",
	"Guidance",
	"Party mage portals",
	"Alerts",
	"Interface",
}

assert(#buttons == #order + 1, "one index button per group, then the Forever addons page")
-- Main's arrival pin added arrivalPin and the line switches added mapLine and minimapLine to the merged list.
assert(#rows == 63, #rows)
local cursor = 0
for index, name in ipairs(order) do
	local button = buttons[index].initializer
	assert(buttons[index].target.name == "Shortest Path Forever", "index buttons sit on the index page")
	assert(button.name == name and button.description == "Open", "the button is named for its group")
	button.callback()
	assert(opened[#opened] == name, "the button opens that group's page")
	for _, key in ipairs(groups[name]) do
		cursor = cursor + 1
		local row = rows[cursor]
		assert(row.target.name == name and row.initializer.setting.key == key, "rows stay in their group, in order")
	end
end
assert(cursor == #rows, "every row belongs to a group")

-- ForeverCore's Forever addons page is the last subpage, with this addon's saved variables.
local family = buttons[#order + 1]
assert(family.target.name == "Shortest Path Forever" and family.initializer.name == "Forever addons")
assert(familyPage and familyPage.category.name == "Shortest Path Forever", "the page sits under the addon's category")
assert(familyPage.db == ns.db, "the page reads and writes this addon's settings")
assert(familyPage.current == "ShortestPathForever", "its own row is this addon's")
assert(familyPage.safeCall == ns.core.SafeCall, "and reports its failures through this addon's SafeCall")
family.initializer.callback()
assert(opened[#opened] == "Forever addons", "the button opens the page")
assert(#opened == secureCalls, "every settings open went through ForeverCore's secure opener (#333)")

-- The rows themselves are unchanged: keys, defaults, tooltips and callbacks.
local function Row(key)
	for _, row in ipairs(rows) do
		if row.initializer.setting.key == key then
			return row.initializer
		end
	end
	error("no row for " .. key)
end
assert(Row("pins").setting.variable == "ShortestPathForever_pins" and Row("pins").setting.default)
assert(
	Row("minimapPins").tooltip
		== "Docks, lifts, the tram and portals. Also under Transport in the minimap's tracking menu."
)
-- The walking line's colour is a preset dropdown, gold by default, and it repaints without replanning.
local routeColor = Row("routeColor")
assert(routeColor.kind == "dropdown" and routeColor.setting.default == "gold", "the route line starts gold")
assert(routeColor.setting.variable == "ShortestPathForever_routeColor", "the choice is saved")
local choices = routeColor.getData()
assert(#choices == 5 and choices[1].value == "gold", "gold leads the presets")
assert(choices[2].text == "White" and choices[5].value == "magenta", "every preset has a label and a key")
routeColor.setting.onChanged(nil, "cyan")
assert(routeColour == "cyan", "choosing a preset repaints the walking line")
-- The walking line can be turned off on either surface, on by default, beside the colour that draws it.
for _, key in ipairs({ "mapLine", "minimapLine" }) do
	local line = Row(key)
	assert(line.kind == "checkbox" and line.setting.default == true, key .. " starts on")
	assert(line.setting.variable == "ShortestPathForever_" .. key, key .. " is saved")
	local before = routeLinesRefreshed
	line.setting.onChanged()
	assert(routeLinesRefreshed == before + 1, key .. " repaints both surfaces at once")
end
assert(Row("mapLine").setting.name == "Line on the world map", "the world map switch names its surface")
assert(Row("minimapLine").setting.name == "Line on the minimap", "the minimap switch names its surface")
assert(
	Row("mapLine").tooltip:find("still guide you", 1, true)
		and Row("minimapLine").tooltip:find("still guide you", 1, true),
	"the tooltips say the guidance stays when the line is off"
)
-- The departures switch names what it hides, so a player looking for Lifts finds it.
assert(
	Row("tracker").setting.name == "Show boat, lift and tram departures in the tracker",
	"the departures switch names boats, lifts and the tram"
)
-- The journey's own block has its switch in Guidance, on by default, and turning it off redraws the tracker.
local journeySteps = Row("journeyTracker")
assert(
	journeySteps.setting.name == "Show journey steps in the objective tracker",
	"the journey switch names the steps and where they show"
)
assert(journeySteps.setting.default == true, "journey steps show in the tracker by default")
assert(
	journeySteps.tooltip:find("arrow", 1, true) and journeySteps.tooltip:find("objective tracker", 1, true),
	"the tooltip says the guidance stays and the block goes"
)
local trackerRefreshes = trackerRefreshed
journeySteps.setting.onChanged()
assert(trackerRefreshed == trackerRefreshes + 1, "the journey switch redraws the tracker")
assert(Row("guideStops").setting.default == true)
assert(Row("taxiRoute").setting.default == true)
assert(Row("flightPathReminder").setting.default == true, "new flight-master reminders are on by default")
local hearth = Row("hearthMinimumSavings")
assert(hearth.kind == "slider" and hearth.setting.default == 0)
assert(hearth.options.format(0) == "Off" and hearth.options.format(90) == "90 Sec", "the slider shows its value")
hearth.setting.onChanged()
assert(policyChanged == 1, "changing Hearthstone savings invalidates the current travel policy")
assert(hearth.options.minValue == 0 and hearth.options.maxValue == 600 and hearth.options.step == 30)
assert(Row("taxiRoute").tooltip:find("flight master", 1, true))
Row("taxiRoute").setting.onChanged()
assert(taxiRefreshed == 1, "flight route updates when its setting changes")
assert(Row("corpse").setting.default == true)
-- Arrival distance: a slider from 5 to 50 yards, at the fixed 15 the journey has always used, labelled as the rest.
local arrivalRow = Row("arrivalDistance")
assert(arrivalRow.kind == "slider", "arrival distance is a slider")
assert(arrivalRow.setting.default == 15, "a journey counts as arrived at 15 yards by default")
assert(arrivalRow.setting.key == "arrivalDistance", "the distance is saved")
assert(
	arrivalRow.options.minValue == 5 and arrivalRow.options.maxValue == 50 and arrivalRow.options.step == 5,
	"the slider runs from 5 to 50 yards in fives"
)
assert(arrivalRow.options.format(30) == "30 yd", "the slider labels its value as a distance")
assert(
	arrivalRow.tooltip:find("dock, lift or flight master", 1, true),
	"the tooltip says a transport stop keeps its own distance"
)
-- The NPC nameplate arrows are guidance furniture and start on, with the friendly-nameplate condition in the tooltip.
assert(Row("npcArrows").setting.default == true, "nameplate arrows are on by default")
assert(Row("npcArrows").tooltip:find("Friendly nameplates", 1, true), "the tooltip says friendly nameplates must be on")
-- Party mage portals are opt-in, and every capital starts ticked for the mage to open.
assert(Row("partyMagePortals").setting.default == false, "party mage portals are off by default")
for _, key in ipairs({
	"partyMageStormwind",
	"partyMageIronforge",
	"partyMageDarnassus",
	"partyMageUndercity",
	"partyMageThunderBluff",
	"partyMageOrgrimmar",
}) do
	assert(Row(key).setting.default == true, key .. " starts ticked")
end
local policyBeforeParty = policyChanged
Row("partyMagePortals").setting.onChanged()
assert(policyChanged == policyBeforeParty + 1, "the party portal setting replans the journey")
-- The compass is on by default: it is the game's own palette rather than a panel on the screen.
assert(Row("compass").setting.default == true)
local mover = Row("compassMove").setting
assert(mover.default == false and mover:GetValue() == false, "the compass starts locked")
mover:SetValue(true)
assert(compassMoving == true and mover:GetValue() == true, "the row unlocks the compass for dragging")
assert(Row("restedxp").setting.default == true, "RestedXP journeys are enabled by default")
assert(Row("guidelime").setting.default == true, "Guidelime journeys are enabled by default")
assert(Row("guidelime").tooltip:find("Guidelime's arrow", 1, true), "the row says the guide arrow steps aside")
Row("guidelime").setting.onChanged()
assert(guidelimeRefreshed == 1, "the row follows its setting")
-- Walks keep out of zones far above your level unless this is off; changing it plans the journey again.
assert(Row("avoidHighZones").setting.default == true, "avoiding high zones is on by default")
local policyBefore = policyChanged
Row("avoidHighZones").setting.onChanged()
assert(policyChanged == policyBefore + 1, "the journey plans again with the new costs")
assert(Row("followRoads").setting.default == false, "following roads is off by default")
Row("followRoads").setting.onChanged()
assert(policyChanged == policyBefore + 2, "following roads plans again with the new costs")
assert(Row("tomtom").setting.default == true)
assert(Row("tomtom").tooltip:find("TomTom", 1, true), "the row names the addon it answers")
Row("tomtom").setting.onChanged()
assert(tomtomRefreshed == 1, "the shim follows its setting")
-- Following TomTom's own arrow is opt-in.
assert(Row("tomtomFollow").setting.default == false, "following TomTom's arrow is off by default")
assert(Row("tomtomFollow").tooltip:find("TomTom", 1, true), "the row names the addon it follows")
Row("tomtomFollow").setting.onChanged()
assert(tomtomFollowRefreshed == 1, "the follower follows its setting")
assert(Row("arrivalSound").setting.default == false, "the arrival sound is off by default")
-- Keeping your own journey across a reload is opt-in; turning it off forgets the one kept.
assert(Row("resumeJourney").setting.default == false, "keeping journeys after a reload is off by default")
local keepChanged = 0
ns.KeepJourneyChanged = function()
	keepChanged = keepChanged + 1
end
Row("resumeJourney").setting.onChanged()
assert(keepChanged == 1, "the kept journey follows its setting")
-- /path report shows the report, its lines run through SafeCall; lines that fail still show the rest.
local shownReport
ns.core.SafeCall = function(_, fn, ...)
	return pcall(fn, ...)
end
ns.core.Report = {
	Text = function(lines)
		return table.concat(lines, "\n")
	end,
	Show = function(text)
		shownReport = text
	end,
}
ns.ReportLines = function()
	return { "Journey: none" }
end
ns.core.Report.Command = function(command)
	if command == "report" then
		local ok, lines = ns.core.SafeCall("report lines", ns.ReportLines)
		ns.core.Report.Show(ns.core.Report.Text(ok and lines or { "Report lines failed: " .. tostring(lines) }))
		return true
	end
	return false
end
env.SlashCmdList.SHORTESTPATHFOREVER("report")
assert(shownReport == "Journey: none", "/path report shows the report")
ns.ReportLines = function()
	error("broke", 0)
end
env.SlashCmdList.SHORTESTPATHFOREVER("report")
assert(shownReport == "Report lines failed: broke", "failing lines are said in their place")
assert(Row("compassTime").setting.default == false, "the compass shows no time unless asked")
-- /path way takes TomTom's /way line, whether or not /way itself is free.
env.SlashCmdList.SHORTESTPATHFOREVER("way Elwynn Forest 42.1 65.3 Goldshire")
assert(ways[1] == "Elwynn Forest 42.1 65.3 Goldshire", "/path way hands on the rest of the line")
env.SlashCmdList.SHORTESTPATHFOREVER("way")
assert(ways[2] == "", "a bare /path way still answers, with its usage")
assert(Row("whatsNew").setting.default == true)
-- New participation defaults on, while the runtime preserves every saved false choice.
assert(Row("stats").setting.default == true, "the travel journal is on by default")
assert(Row("statsShare").setting.default == true, "and sharing its stats is too")
assert(Row("stats").tooltip:find("On by default", 1, true), "the journal's tooltip says it is on")
assert(Row("statsShare").tooltip:find("On unless you turn it off", 1, true), "sharing is opt-out")
assert(Row("statsShare").tooltip:find("Forever Leaderboards", 1, true), "sharing puts the player on the boards")
assert(Row("statsShare").tooltip:find("player-reported", 1, true), "shared records are still marked unverified")
Row("stats").setting.onChanged()
Row("statsShare").setting.onChanged()
assert(sharingChanges == 2, "both recording and sharing switches update the active transport")
env.SlashCmdList.SHORTESTPATHFOREVER("leaderboard")
assert(leaderboardOpened == true, "the leaderboard command opens the shared window on this addon's tab")
local trackerSlider = Row("trackerScale")
assert(trackerSlider.kind == "slider" and trackerSlider.setting.default == 100, "tracker scale defaults to 100%")
assert(trackerSlider.options.minValue == 50 and trackerSlider.options.maxValue == 200, "tracker scale is a percentage")
assert(trackerSlider.options.format(150) == "150%", "the tracker slider shows a percent")
assert(trackerSlider.setting:GetValue() == 100, "the tracker slider reads the shared host")
trackerSlider.setting:SetValue(150)
assert(trackerScale == 1.5, "the tracker slider drives the shared host scale")
local compassSlider = Row("compassScale")
assert(compassSlider.kind == "slider" and compassSlider.setting.default == 100, "compass scale defaults to 100%")
assert(compassSlider.options.format(150) == "150%", "the compass slider shows a percent")
compassSlider.setting.onChanged(nil, 150)
assert(compassScaled == 150, "the compass slider rescales the compass")
local arrowSlider = Row("arrowScale")
assert(arrowSlider.kind == "slider" and arrowSlider.setting.default == 100, "arrow scale defaults to 100%")
arrowSlider.setting.onChanged(nil, 150)
assert(arrowScaled == 150, "the arrow slider rescales the arrow")
local arrowLabelRow = Row("arrowLabel")
assert(arrowLabelRow.kind == "dropdown", "the arrow label is a dropdown")
assert(arrowLabelRow.setting.default == "distance", "the arrow starts with the distance")
assert(arrowLabelRow.setting.variable == "ShortestPathForever_arrowLabel", "the label choice is saved")
local labelChoices = arrowLabelRow.getData()
assert(#labelChoices == 3 and labelChoices[1].value == "distance", "distance leads the choices")
assert(labelChoices[2].value == "time" and labelChoices[3].value == "both", "time and both follow the distance")
arrowLabelRow.setting.onChanged(nil, "time")
assert(arrowLabelSet == "time", "choosing the time refreshes the arrow at once")
-- The stop's objectives under the arrow have their own switch, on by default, beside the label that sits above them.
local arrowObjectiveRow = Row("arrowObjectives")
assert(arrowObjectiveRow.kind == "checkbox", "objectives under the arrow are a checkbox")
assert(arrowObjectiveRow.setting.default == true, "the arrow lists objectives by default")
assert(arrowObjectiveRow.setting.key == "arrowObjectives", "the switch is saved")
assert(
	arrowObjectiveRow.tooltip:find("pin shown when you reach a stop", 1, true),
	"the tooltip says the arrival pin keeps its own lines"
)
arrowObjectiveRow.setting.onChanged()
assert(arrowObjectivesChanged == 1, "the switch redraws the arrow's lines at once")
local arrowMover = Row("arrowMove").setting
arrowMover:SetValue(true)
assert(arrowMoving == true and arrowMover:GetValue() == true, "the row lets the arrow be dragged")
arrowMover:SetValue(false)
local backgroundSlider = Row("compassBackground")
assert(backgroundSlider.kind == "slider" and backgroundSlider.setting.default == 0, "no compass background by default")
assert(
	backgroundSlider.options.minValue == 0 and backgroundSlider.options.format(40) == "40%",
	"background is a percent"
)
backgroundSlider.setting.onChanged(nil, 40)
assert(compassBackdrop == 40, "the background slider darkens the compass")
Row("pins").setting.onChanged()
assert(refreshed == 1, "value callbacks still fire")
print("settings: ok")

local attachment = Row("trackerAttached").setting
assert(attachment:GetValue() == true, "tracker starts attached")
attachment:SetValue(false)
assert(not attachment:GetValue(), "toggle changes shared host")
assert(attachmentNotified == "ShortestPathForever_trackerAttached", "proxy notified")
trackerState.attached = true
attachmentChanged()
assert(attachment:GetValue(), "external reattach updates proxy")

-- Lock starts off, sits right after the detach row, and drives the shared host rather than a copy of its own.
local lock = Row("trackerLocked").setting
assert(lock.name == "Lock the tracker" and lock.default == false, "the lock row is named and off by default")
assert(lock:GetValue() == false, "the tracker starts unlocked")
lock:SetValue(true)
assert(trackerState.locked == true and lock:GetValue(), "locking writes the shared host settings")
lock:SetValue(false)
assert(trackerState.locked == false and not lock:GetValue(), "unlocking writes them back")
