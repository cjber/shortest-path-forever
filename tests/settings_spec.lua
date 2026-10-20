-- Settings rows must reach their layout only through Settings.RegisterInitializer, which inserts them from
-- Blizzard's secure attribute delegate. Settings.CreateCheckbox inserts from the caller instead, which taints
-- the settings search, and a restricted button in its results (Social's Discord Sign In) is then blocked and
-- blamed on this addon. The index buttons go through RegisterInitializer too, and keep themselves out of search.
local rows, buttons, settings = {}, {}, {}
local opened = {}
local canvas, familyPanel

local attachmentNotified, attachmentChanged
local trackerState = { attached = true }
local trackerScale, compassScaled, compassBackdrop = 1, nil, nil
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
		VarType = { Boolean = "boolean", Number = "number" },
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
		RegisterCanvasLayoutSubcategory = function(parent, frame, name)
			canvas = { parent = parent, frame = frame, name = name }
			return {
				name = name,
				parent = parent,
				GetID = function(self)
					return self.name
				end,
			}
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
		OpenToCategory = function(id)
			opened[#opened + 1] = id
		end,
	},
	CreateSettingsButtonInitializer = function(name, description, callback, tags, addSearchTags)
		assert(tags == nil and addSearchTags == false, "index buttons stay out of the settings search")
		return { kind = "button", name = name, description = description, callback = callback }
	end,
	SlashCmdList = {},
}, { __index = _G })

local refreshed, taxiRefreshed, policyChanged, tomtomRefreshed = 0, 0, 0, 0
local compassMoving = false
local arrowMoving, arrowScaled = false, nil
local tomtomFollowRefreshed, ways = 0, {}
-- Core/Core.lua's defaults: every row on.
local ns = {
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
		CreatePanel = function(parent, db, current, locale)
			familyPanel = { parent = parent, db = db, current = current, locale = locale }
			return familyPanel
		end,
	},
	db = {},
	Defaults = setmetatable({
		hearthMinimumSavings = 0,
		compassScale = 100,
		arrowScale = 100,
		compassBackground = 0,
		tomtomFollow = false,
		compassTime = false,
		arrivalSound = false,
		resumeJourney = false,
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
	SetCompassBackground = function(value)
		compassBackdrop = value
	end,
}
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
	},
	Transport = { "mapRoutes", "otherFaction", "tracker", "share" },
	Guidance = {
		"trackerAttached",
		"trackerLocked",
		"journey",
		"resumeJourney",
		"tomtom",
		"tomtomFollow",
		"restedxp",
		"avoidHighZones",
		"teleports",
		"hearthMinimumSavings",
		"guideStops",
		"taxiRoute",
		"corpse",
	},
	Alerts = { "alerts", "alertSound", "arrivalSound" },
	Interface = {
		"journeyTracker",
		"arrow",
		"arrowMove",
		"arrowScale",
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
local order = { "Map marks", "Transport", "Guidance", "Alerts", "Interface" }

assert(#buttons == #order + 1, "one index button per group, then the Forever addons page")
assert(#rows == 41, #rows)
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

-- The shared Forever addons page (UI/ForeverFamily.lua) is the last subpage, with this addon's saved variables.
local family = buttons[#order + 1]
assert(family.target.name == "Shortest Path Forever" and family.initializer.name == "Forever addons")
assert(canvas and canvas.name == "Forever addons" and canvas.parent.name == "Shortest Path Forever")
assert(canvas.frame == familyPanel and familyPanel.db == ns.db, "the page reads and writes this addon's settings")
assert(familyPanel.current == "ShortestPathForever", "its own row is this addon's")
assert(familyPanel.locale == ns.L, "and it reads in this addon's own translations")
family.initializer.callback()
assert(opened[#opened] == "Forever addons", "the button opens the page")

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
assert(Row("guideStops").setting.default == true)
assert(Row("taxiRoute").setting.default == true)
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
-- The compass is on by default: it is the game's own palette rather than a panel on the screen.
assert(Row("compass").setting.default == true)
local mover = Row("compassMove").setting
assert(mover.default == false and mover:GetValue() == false, "the compass starts locked")
mover:SetValue(true)
assert(compassMoving == true and mover:GetValue() == true, "the row unlocks the compass for dragging")
assert(Row("restedxp").setting.default == true, "RestedXP journeys are enabled by default")
-- Walks keep out of zones far above your level unless this is off; changing it plans the journey again.
assert(Row("avoidHighZones").setting.default == true, "avoiding high zones is on by default")
local policyBefore = policyChanged
Row("avoidHighZones").setting.onChanged()
assert(policyChanged == policyBefore + 1, "the journey plans again with the new costs")
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
ns.SafeCall = function(_, fn, ...)
	return pcall(fn, ...)
end
ns.Report = {
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
