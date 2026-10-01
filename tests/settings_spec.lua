-- Settings rows must reach their layout only through Settings.RegisterInitializer, which inserts them from
-- Blizzard's secure attribute delegate. Settings.CreateCheckbox inserts from the caller instead, which taints
-- the settings search, and a restricted button in its results (Social's Discord Sign In) is then blocked and
-- blamed on this addon. The index buttons go through RegisterInitializer too, and keep themselves out of search.
local rows, buttons, settings = {}, {}, {}
local opened = {}

local attachmentNotified, attachmentChanged
local trackerState = { attached = true }
local env = setmetatable({
	Settings = {
		RegisterProxySetting = function(category, variable, varType, name, default, get, set)
			local setting = {
				category = category,
				variable = variable,
				key = "trackerAttached",
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
			return { minValue = minimum, maxValue = maximum, step = step }
		end,
		CreateSliderInitializer = function(setting, options, tooltip)
			assert(setting.varType == "number" and options)
			return { kind = "slider", setting = setting, options = options, tooltip = tooltip }
		end,
		RegisterInitializer = function(target, initializer)
			if initializer.kind == "button" then
				buttons[#buttons + 1] = { target = target, initializer = initializer }
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

local refreshed, taxiRefreshed, buttonRefreshed = 0, 0, 0
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
	},
	db = {},
	Defaults = setmetatable({ hearthMinimumSavings = 0 }, {
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
	RefreshRouteButton = function()
		buttonRefreshed = buttonRefreshed + 1
	end,
}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
setfenv(assert(loadfile("UI/Settings.lua")), env)("ShortestPathForever", ns)

-- The index page is one button per group; each opens that group's page. The groups divide the old flat list, and
-- every row keeps its key, default, tooltip and callback.
local groups = {
	["Map marks"] = { "pins", "transit", "portals", "mapFlightMasters", "minimapPins" },
	Transport = { "mapRoutes", "otherFaction", "tracker", "share" },
	Guidance = {
		"trackerAttached",
		"journey",
		"teleports",
		"hearthMinimumSavings",
		"guideStops",
		"taxiRoute",
		"corpse",
	},
	Alerts = { "alerts", "alertSound" },
	Interface = { "compass", "routeButton", "whatsNew" },
}
local order = { "Map marks", "Transport", "Guidance", "Alerts", "Interface" }

assert(#buttons == #order, "one index button per group")
assert(#rows == 21, #rows)
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
assert(Row("minimapPins").tooltip == "Also under Transport in the minimap's tracking menu.")
assert(Row("guideStops").setting.default == true)
assert(Row("taxiRoute").setting.default == true)
local hearth = Row("hearthMinimumSavings")
assert(hearth.kind == "slider" and hearth.setting.default == 0)
assert(hearth.options.minValue == 0 and hearth.options.maxValue == 600 and hearth.options.step == 30)
assert(Row("taxiRoute").tooltip:find("flight master", 1, true))
Row("taxiRoute").setting.onChanged()
assert(taxiRefreshed == 1, "flight route updates when its setting changes")
assert(Row("corpse").setting.default == true)
-- The compass is on by default: it is the game's own palette rather than a panel on the screen.
assert(Row("compass").setting.default == true)
assert(Row("routeButton").setting.default == true)
assert(Row("routeButton").tooltip:find("gold", 1, true), "the route button says what its colour means")
Row("routeButton").setting.onChanged()
assert(buttonRefreshed == 1, "the minimap button follows its setting")
assert(Row("whatsNew").setting.default == true)
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
