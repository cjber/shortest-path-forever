-- The client the UI checks run against: stub frames and client APIs. tests/ui_map.lua follows it in one chunk,
-- so the checks appended after both share their locals.
local BLIZZARD_UI = (os.getenv("SPF_BLIZZARD_UI") or "tools/.cache/blizzard-ui") .. "/Interface/AddOns/"
-- Loads the addon in toc order against stubs, fires ADDON_LOADED, runs tickers and a fake ride.
local T, frames, tickers = 0, {}, {}
local uiScale = 1
local shiftDown, mouseFoci = true, {}
local arrowFrame
local posX, posY, posMap = -1005.6, -3841.6, 1
local posZ = 0
local errors, lineCreations, waypointCalls = {}, 0, 0
local waypoint, supertracked = nil, false
local trackedQuest, playerUiMap = 0, nil
local onTaxi, facing = false, 0
local moving, combat = false, false
local mapOpens = 0
_G.IsPlayerMoving = function()
	return moving
end
_G.InCombatLockdown = function()
	return combat
end
local cvars = { rotateMinimap = "0", questPOI = "1" }
local function noop() end
local mt = {
	__index = function(t, k)
		if k:match("^%u") then
			return noop
		end
	end,
}
local function animationGroup(owner)
	local group = { owner = owner, animations = {}, plays = 0 }
	function group:CreateAnimation(kind)
		local animation = { kind = kind }
		for _, key in ipairs({ "Duration", "Degrees", "FromAlpha", "ToAlpha", "Smoothing", "Order", "Target" }) do
			animation["Set" .. key] = function(self, value)
				self[key] = value
			end
		end
		self.animations[#self.animations + 1] = animation
		return animation
	end
	function group:SetLooping(value)
		self.looping = value
	end
	function group:Play()
		self.playing = true
		self.plays = self.plays + 1
	end
	function group:Restart()
		self:Play()
	end
	function group:Stop()
		self.playing = false
	end
	function group:IsPlaying()
		return self.playing == true
	end
	return group
end
local function visibilityChanged(frame, shown)
	local script = frame.scripts[shown and "OnShow" or "OnHide"]
	if script then
		script(frame)
	end
	for _, child in ipairs(frame.children or {}) do
		if child:IsShown() then
			visibilityChanged(child, shown)
		end
	end
end
local function font()
	local f = { text = "" }
	function f:EnableMouse(value)
		self.mouseEnabled = value
	end
	function f:SetText(v)
		self.text = v
	end
	function f:GetText()
		return self.text
	end
	function f:GetStringWidth()
		return #self.text * 6
	end
	function f:GetHeight()
		return 12
	end
	return setmetatable(f, mt)
end
local fontmt = {
	__index = function(t, k)
		if k == "SetFormattedText" then
			return function(self, fmt, ...)
				self.text = string.format(fmt, ...)
			end
		end
		if k == "SetText" then
			return function(self, v)
				self.text = v
			end
		end
		return noop
	end,
}
local function stubframe()
	local f = setmetatable({ scripts = {} }, mt)
	function f:CreateFontString()
		return setmetatable({}, fontmt)
	end
	function f:GetEffectiveScale()
		return (self.parent and self.parent.GetEffectiveScale and self.parent:GetEffectiveScale() or uiScale)
			* (self.scale or 1)
	end
	function f:SetAlpha(v)
		self.alpha = v
	end
	function f:CreateAnimationGroup()
		return animationGroup(self)
	end
	function f:CreateTexture()
		local texture = setmetatable({ parent = self }, mt)
		function texture:SetAtlas(v)
			self.atlas = v
			if v == "Navigation-Tracked-Arrow" then
				arrowFrame = f
			end
		end
		function texture:CreateAnimationGroup()
			return animationGroup(self)
		end
		function texture:SetSize(w, h)
			self.width, self.height = w, h
		end
		function texture:SetAllPoints(owner)
			self.allPoints = owner or self.parent
		end
		function texture:ClearAllPoints()
			self.allPoints, self.anchor = nil, nil
		end
		function texture:SetBlendMode(value)
			self.blendMode = value
		end
		function texture:SetRotation(v)
			self.rotation = v
		end
		function texture:SetTexCoord(...)
			self.coords = { ... }
		end
		function texture:SetAlpha(v)
			self.alpha = v
		end
		function texture:SetVertexColor(...)
			self.color = { ... }
		end
		function texture:SetShown(v)
			self.hidden = not v
		end
		function texture:SetPoint(...)
			self.anchor = { ... }
		end
		function texture:Show()
			self.hidden = false
		end
		function texture:Hide()
			self.hidden = true
		end
		self.textures = self.textures or {}
		self.textures[#self.textures + 1] = texture
		return texture
	end
	function f:SetScript(n, fn)
		self.scripts[n] = fn
	end
	function f:RegisterEvent(event)
		self.events = self.events or {}
		self.events[event] = true
	end
	function f:RegisterUnitEvent(event, unit)
		self:RegisterEvent(event)
		self.units = self.units or {}
		self.units[event] = unit
	end
	function f:UnregisterEvent(event)
		if self.events then
			self.events[event] = nil
		end
	end
	function f:SetSize(w, h)
		self.width, self.height = w, h
	end
	function f:SetWidth(value)
		self.width = value
	end
	function f:SetHeight(value)
		self.height = value
	end
	function f:EnableMouse(value)
		self.mouseEnabled = value
	end
	function f:SetText(v)
		self.text = v
	end
	function f:SetAllPoints(owner)
		self.width, self.height = owner:GetWidth(), owner:GetHeight()
	end
	function f:GetWidth()
		return self.width
	end
	function f:GetHeight()
		return self.height
	end
	function f:GetTop()
		return self.top or (self.parent and self.parent.GetHeight and self.parent:GetHeight()) or 0
	end
	function f:GetBottom()
		return self:GetTop() - (self:GetHeight() or 0)
	end
	function f:SetPoint(...)
		self.anchor = { ... }
	end
	function f:IsShown()
		return not self.hidden
	end
	function f:IsVisible()
		return not self.hidden and (not self.parent or not self.parent.IsVisible or self.parent:IsVisible())
	end
	function f:SetShown(value)
		if value then
			self:Show()
		else
			self:Hide()
		end
	end
	function f:Show()
		local wasVisible = self:IsVisible()
		self.hidden = false
		if not wasVisible and self:IsVisible() then
			visibilityChanged(self, true)
		end
	end
	function f:Hide()
		if self.hidden then
			return
		end
		local wasVisible = self:IsVisible()
		self.hidden = true
		if wasVisible then
			visibilityChanged(self, false)
		end
	end
	function f:CreateLine(_, layer, _, sublevel)
		lineCreations = lineCreations + 1
		local line = { parent = self, layer = layer, sublevel = sublevel or 0 }
		function line:SetColorTexture(...)
			self.textureColor = { ... }
		end
		function line:SetTexture(path)
			self.texture = path
		end
		function line:SetAlpha(v)
			self.alpha = v
		end
		function line:SetAtlas(v)
			self.atlas = v
		end
		function line:SetVertexColor(...)
			self.color = { ... }
		end
		function line:SetThickness(v)
			self.thickness = v
		end
		function line:SetStartPoint(point, owner, x, y)
			assert(point == "TOPLEFT" and x >= -0.0001 and x <= owner:GetWidth() + 0.0001)
			assert(y <= 0.0001 and y >= -owner:GetHeight() - 0.0001)
			self.start = { x, y }
		end
		function line:SetEndPoint(point, owner, x, y)
			assert(point == "TOPLEFT" and x >= -0.0001 and x <= owner:GetWidth() + 0.0001)
			assert(y <= 0.0001 and y >= -owner:GetHeight() - 0.0001)
			self.finish = { x, y }
		end
		function line:Show()
			self.shown = true
		end
		function line:Hide()
			self.shown = false
		end
		return line
	end
	f.Header = {
		SetScript = noop,
		EnableMouse = noop,
	}
	frames[#frames + 1] = f
	return f
end
_G.CreateFrame = function(_, name, parent, template)
	local f = stubframe()
	f.name, f.parent, f.template = name, parent, template
	if parent then
		parent.children = parent.children or {}
		parent.children[#parent.children + 1] = f
	end
	if name then
		_G[name] = f
	end
	if template == "SpinnerTemplate" then
		-- Read the client template and run its real visibility scripts, rather than assuming the artwork.
		local ui = BLIZZARD_UI .. "Blizzard_SharedXML/"
		assert(loadfile(ui .. "Spinner.lua"))()
		Mixin(f, SpinnerMixin)
		f.Shadow = false
		local file = assert(io.open(ui .. "Spinner.xml"))
		local xml = file:read("*a")
		file:close()
		for attrs in xml:gmatch("<Texture (.-)/>") do
			local key, atlas = attrs:match('parentKey="(.-)"'), attrs:match('atlas="(.-)"')
			local texture = f:CreateTexture()
			texture:SetAtlas(atlas)
			texture:SetAllPoints(f)
			texture:SetBlendMode(attrs:match('alphaMode="(.-)"') or "BLEND")
			f[key] = texture
		end
		f.Anim = f:CreateAnimationGroup()
		f.Anim:SetLooping(xml:match('<AnimationGroup.-looping="(.-)"'))
		for attrs in xml:gmatch("<Rotation (.-)>") do
			local rotation = f.Anim:CreateAnimation("Rotation")
			rotation:SetTarget(f[attrs:match('childKey="(.-)"')])
			rotation:SetDuration(tonumber(attrs:match('duration="(.-)"')))
			rotation:SetDegrees(tonumber(attrs:match('degrees="(.-)"')))
			rotation:SetOrder(tonumber(attrs:match('order="(.-)"')))
		end
		f:SetScript("OnShow", f.OnShow)
		f:SetScript("OnHide", f.OnHide)
		f:OnShow()
	end
	if template == "ObjectiveTrackerModuleTemplate" then
		f.liveBlocks, f.layoutOrder = {}, {}
		function f:SetContainer(container)
			self.parentContainer = container
		end
		function f:Update()
			self:MarkDirty()
		end
		function f:GetContentsHeight()
			return #self.layoutOrder > 0 and 25 + #self.layoutOrder * 40 or 0
		end
		f.Header.Text = font()
		function f:SetHeader(text)
			self.Header.Text:SetText(text)
		end
		function f:GetBlock(id)
			local b = self.liveBlocks[id]
			if not b then
				b = { id = id, HeaderText = font(), lines = {} }
				function b:SetHeader(text)
					self.HeaderText:SetText(text)
				end
				function b:SetStringText(fs, text, full, color, highlight)
					fs:SetText(text)
					fs.colorStyle = color
					return fs:GetHeight()
				end
				function b:AddObjective(key, text, template, full, dash, color)
					local line = {
						Text = font(),
						used = true,
						GetHeight = function()
							return 12
						end,
					}
					line.Text:SetText(text)
					line.Text.colorStyle = color
					self.lines[key] = line
					return line
				end
				function b:GetExistingLine(key)
					return self.lines[key]
				end
				self.liveBlocks[id] = b
			end
			b.used = true
			return b
		end
		function f:GetExistingBlock(id)
			return self.liveBlocks[id]
		end
		function f:IsDirty()
			return false
		end
		function f:LayoutBlock(b)
			self.layoutOrder[#self.layoutOrder + 1] = b.id
			return true
		end
		function f:MarkDirty()
			self.layoutOrder = {}
			for _, b in pairs(self.liveBlocks) do
				b.used = false
				b.lines = {}
			end
			self:LayoutContents()
		end
	end
	return f
end
_G.GetTime = function()
	return T
end
_G.GetServerTime = function()
	return math.floor(1790000000 + T)
end
-- Translation files (Locales/<locale>.lua) ask for the client's language.
_G.GetLocale = function()
	return "enUS"
end
_G.GetRealmName = function()
	return "Test"
end
_G.GetNormalizedRealmName = function()
	return "Test"
end
_G.UnitPosition = function()
	return posX, posY, posZ, posMap
end
_G.UnitOnTaxi = function()
	return onTaxi
end
-- A ghost, for the corpse-run state; a UI check sets it directly when it drives dead play.
local ghost = false
_G.UnitIsGhost = function()
	return ghost
end
_G.UnitIsDeadOrGhost = _G.UnitIsGhost
_G.GetPlayerFacing = function()
	return facing
end
_G.C_Navigation = { GetFrame = noop }
_G.GetMinimapShape = noop
-- The corpse's map position while ghost is true; nil is the ordinary living case.
local corpsePosition
_G.C_DeathInfo = {
	GetCorpseMapPosition = function()
		return corpsePosition
	end,
}
_G.GetCVar = function(k)
	return cvars[k]
end
_G.GetCVarBool = function(k)
	return cvars[k] == "1"
end
-- Whether this client has the QuestPOIFrame widget the world map's area pin is; a check body may turn it off before
-- the first area is wanted.
local blobWidget = true
_G.C_XMLUtil = {
	GetTemplateInfo = function(template)
		if template == "ShortestPathForeverAreaPinTemplate" and not blobWidget then
			return nil
		end
		return { type = "Frame" }
	end,
}
_G.Minimap = stubframe()
Minimap:SetSize(200, 200)
-- The minimap's own quest blob textures, which the addon swaps while the player stands in an objective area.
for _, key in ipairs({ "Inside", "Outside", "Ring" }) do
	rawset(Minimap, "SetQuestBlob" .. key .. "Texture", function(self, texture)
		self["questBlob" .. key] = texture
	end)
end
-- The client's own answer for each quest, which the check bodies set directly.
local insideQuestBlob = {}
_G.C_Minimap = {
	GetViewRadius = function()
		return 200
	end,
	IsInsideQuestBlob = function(questID)
		return insideQuestBlob[questID] == true
	end,
}
_G.UnitName = function()
	return "Me"
end
_G.Ambiguate = function(s)
	return (s:gsub("%-.*", ""))
end
_G.IsInGuild = function()
	return true
end
_G.IsInGroup = function()
	return false
end
_G.IsInRaid = function()
	return false
end
_G.IsInInstance = function()
	return false
end
local function color(r, g, b)
	return {
		GetRGBA = function()
			return r, g, b, 1
		end,
		WrapTextInColorCode = function(_, s)
			return s
		end,
	}
end
_G.OBJECTIVE_TRACKER_COLOR = { Normal = {}, NormalHighlight = {}, Header = {} }
_G.CreateColor = color
_G.NORMAL_FONT_COLOR = color(1, 0.82, 0)
_G.ORANGE_FONT_COLOR = color(1, 0.5, 0)
_G.AM_PIN_SCALE_STYLE_WITH_TERRAIN = 3
_G.GRAY_FONT_COLOR = _G.NORMAL_FONT_COLOR
_G.HIGHLIGHT_FONT_COLOR = color(1, 1, 1)
_G.ChatTypeInfo = { RAID_WARNING = {} }
_G.RaidWarningUtil = { AddMessage = noop }
_G.PlaySound = noop
_G.PlaySoundFile = noop
-- A character with a hearthstone and no recorded bind point: no teleport edges, as after a fresh install.
_G.GetBindLocation = function()
	return "Auberdine"
end
_G.C_SpellBook = {
	IsSpellKnown = function()
		return false
	end,
}
_G.C_Item = {
	GetItemCount = function(id)
		return id == 6948 and 1 or 0
	end,
	GetItemCooldown = function()
		return 0, 0, 1
	end,
}
_G.FlashClientIcon = noop
_G.SOUNDKIT = {}
_G.UNKNOWN = "Unknown"
_G.geterrorhandler = function()
	return function(e)
		errors[#errors + 1] = e
		print("ERROR", e)
	end
end
_G.GetUnitSpeed = function()
	return 0, 7, 7, 4.7
end
_G.IsShiftKeyDown = function()
	return shiftDown
end
-- Any modifier, for the map pin's Ends menu; separate from shift so a caller can tell the two apart.
local modifierDown = false
_G.IsModifierKeyDown = function()
	return modifierDown
end
_G.GetMouseFoci = function()
	return mouseFoci
end
_G.GetQuestUiMapID = function()
	return 0
end
_G.C_QuestLog = {
	GetQuestsOnMap = function()
		return {}
	end,
	GetNextWaypoint = noop,
	GetNextWaypointForMap = noop,
	GetTitleForQuestID = noop,
	IsComplete = function()
		return false
	end,
}
_G.MapCanvasMixin = { MouseAction = { Up = 1, Down = 2, Click = 3 } }
_G.POIButtonUtil = { Style = { Waypoint = 1 } }
_G.GetTaxiMapID = function()
	return nil
end
_G.C_Texture = {
	GetAtlasInfo = function()
		return { width = 36, height = 44 }
	end,
}
_G.C_TaxiMap = {
	ShouldMapShowTaxiNodes = function()
		return false
	end,
	GetTaxiNodesForMap = function(id)
		return {}
	end,
	GetAllTaxiNodes = function()
		return {}
	end,
}
local function fireEvent(event, ...)
	for _, f in ipairs(frames) do
		if
			f.events
			and f.events[event]
			and (not f.units or not f.units[event] or f.units[event] == (...))
			and f.scripts.OnEvent
		then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end
-- Water walking: no buff is up and no spell is known.
_G.C_UnitAuras = { GetPlayerAuraBySpellID = noop }
_G.IsPlayerSpell = function()
	return false
end
_G.C_Spell = {
	GetSpellName = function(id)
		return ({ [546] = "Water Walking", [1706] = "Levitate" })[id]
	end,
}
_G.C_SuperTrack = {
	SetSuperTrackedUserWaypoint = function(v)
		supertracked = v
		fireEvent("SUPER_TRACKING_CHANGED")
	end,
	IsSuperTrackingUserWaypoint = function()
		return supertracked
	end,
	GetSuperTrackedQuestID = function()
		return trackedQuest
	end,
	GetHighestPrioritySuperTrackingType = function()
		return supertracked and "UserWaypoint" or trackedQuest ~= 0 and "Quest" or nil
	end,
	SetSuperTrackedQuestID = function(id)
		trackedQuest = id
		supertracked = false
		fireEvent("SUPER_TRACKING_CHANGED")
	end,
}
_G.UiMapPoint = {
	CreateFromCoordinates = function(m, x, y, z)
		return { uiMapID = m, position = CreateVector2D(x, y), z = z }
	end,
	CreateFromVector2D = function(m, v, z)
		return { uiMapID = m, position = v, z = z }
	end,
}
_G.Enum = {
	FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 },
	FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 },
	UIMapType = { Continent = 2, Zone = 3 },
	SendAddonMessageResult = {
		InvalidPrefix = 1,
		InvalidChatType = 4,
		InvalidChannel = 7,
	},
}
_G.CreateVector2D = function(x, y)
	return {
		x = x,
		y = y,
		GetXY = function(self)
			return self.x, self.y
		end,
	}
end
_G.C_Map = {
	OpenWorldMap = function()
		mapOpens = mapOpens + 1
	end,
	GetBestMapForUnit = function()
		return playerUiMap or (posMap == 0 and 1415 or 1414)
	end,
	HasUserWaypoint = function()
		return waypoint ~= nil
	end,
	GetMapPosFromWorldPos = function(cont, v, override)
		local x, y = v:GetXY()
		local m = cont == 0 and 1415 or 1414
		-- Each continent is covered by one zone, numbered 1400 below it, with the continent's own fractions.
		if override and override ~= m and override ~= m - 1400 then
			return nil
		end
		return override or m, CreateVector2D(0.5 - y / 25000, 0.5 - x / 25000)
	end,
	GetMapInfo = function(id)
		return { mapID = id, mapType = id >= 1400 and 2 or 3, parentMapID = 0, name = "Map" .. id }
	end,
	GetMapInfoAtPosition = function(id)
		return id >= 1400 and C_Map.GetMapInfo(id - 1400) or nil
	end,
	GetWorldPosFromMapPos = function(m, v)
		local x, y = v:GetXY()
		return m == 1415 and 0 or 1, CreateVector2D((0.5 - y) * 25000, (0.5 - x) * 25000)
	end,
	CanSetUserWaypointOnMap = function()
		return true
	end,
	SetUserWaypoint = function(p)
		waypointCalls = waypointCalls + 1
		waypoint = p
		fireEvent("USER_WAYPOINT_UPDATED")
		return true
	end,
	GetUserWaypoint = function()
		return waypoint
			and {
				uiMapID = waypoint.uiMapID,
				position = { x = waypoint.position.x, y = waypoint.position.y },
				z = waypoint.z,
			}
	end,
	GetUserWaypointPositionForMap = function(m)
		if not waypoint then
			return
		end
		local continent, world =
			C_Map.GetWorldPosFromMapPos(waypoint.uiMapID, CreateVector2D(waypoint.position.x, waypoint.position.y))
		if not world then
			return
		end
		local projected, position = C_Map.GetMapPosFromWorldPos(continent, world, m)
		if projected == m then
			return position
		end
	end,
	ClearUserWaypoint = function()
		waypoint = nil
		fireEvent("USER_WAYPOINT_UPDATED")
	end,
}
_G.EventUtil = {
	ContinueAfterAllEvents = function(fn)
		fn()
	end,
}
local pending = {}
_G.C_Timer = {
	After = function(s, fn)
		pending[#pending + 1] = { at = T + s, fn = fn }
	end,
	NewTicker = function(s, fn)
		local ticker = { every = s, fn = fn, next = T + s }
		function ticker:Cancel()
			self.cancelled = true
		end
		tickers[#tickers + 1] = ticker
		return ticker
	end,
}
_G.C_ChatInfo = {
	RegisterAddonMessagePrefix = noop,
	SendAddonMessage = function()
		return 0
	end,
}
-- The settings surface, recorded so a UI check can drive the real rows and index buttons: each option's own
-- value-changed callback, and each subpage button's OpenToCategory target.
local addonSettings, settingsRows, settingsButtons, openedCategories = {}, {}, {}, {}
_G.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
_G.OFF = _G.OFF or "Off"
_G.SecondsToTime = _G.SecondsToTime or function(seconds)
	return seconds .. " Sec"
end
_G.Settings = setmetatable({
	VarType = {},
	RegisterVerticalLayoutCategory = function(name)
		return {
			name = name,
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
	RegisterProxySetting = function(category, variable, _, name, default, get, set)
		local st = {
			category = category,
			variable = variable,
			key = variable:match("_(%a+)$"),
			name = name,
			default = default,
			GetValue = get,
			SetValue = function(_, value)
				set(value)
			end,
		}
		addonSettings[#addonSettings + 1] = st
		return st
	end,
	RegisterAddOnSetting = function(category, variable, key, db, _, name, default)
		if db[key] == nil then
			db[key] = default
		end
		local st = { category = category, variable = variable, key = key, name = name, default = default }
		function st:SetValueChangedCallback(fn)
			st.cb = fn
		end
		function st:GetValue()
			return db[key]
		end
		function st:SetValue(v)
			assert(type(v) == type(default), "a setting value matches its registered type")
			db[key] = v
			if st.cb then
				st.cb()
			end
		end
		addonSettings[#addonSettings + 1] = st
		return st
	end,
	CreateCheckboxInitializer = function(setting, options, tooltip)
		return { kind = "checkbox", setting = setting, options = options, tooltip = tooltip }
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
		return { kind = "slider", setting = setting, options = options, tooltip = tooltip }
	end,
	RegisterInitializer = function(target, initializer)
		if initializer and initializer.kind == "button" then
			settingsButtons[#settingsButtons + 1] = { target = target, initializer = initializer }
		else
			settingsRows[#settingsRows + 1] = { target = target, initializer = initializer }
		end
	end,
	OpenToCategory = function(id)
		openedCategories[#openedCategories + 1] = id
	end,
}, mt)
_G.CreateSettingsButtonInitializer = function(name, description, callback, tags, addSearchTags)
	return {
		kind = "button",
		name = name,
		description = description,
		callback = callback,
		tags = tags,
		addSearchTags = addSearchTags,
	}
end
local menus, context = {}, {}
_G.MenuUtil = {
	CreateContextMenu = function(owner, generator)
		context = {}
		local root = {
			CreateCheckbox = function(_, text, get, set)
				context[text] = { get = get, click = set }
			end,
			CreateButton = function(_, text, click)
				context[text] = { click = click }
				return { SetEnabled = noop }
			end,
		}
		generator(owner, root)
		return stubframe()
	end,
}
_G.Menu = {
	ModifyMenu = function(tag, fn)
		menus[tag] = fn
	end,
}
_G.UnitFactionGroup = function()
	return "Alliance"
end
_G.Lerp = function(a, b, t)
	return a + (b - a) * t
end
_G.Saturate = function(v)
	return math.max(0, math.min(1, v))
end
_G.Clamp = function(v, a, b)
	return math.max(a, math.min(b, v))
end
_G.math.atan2 = math.atan2 or function(y, x)
	return math.atan(y, x)
end
local tip = {}
_G.GameTooltip_SetTitle = function(_, t)
	tip = { "# " .. t }
end
_G.GameTooltip_AddColoredLine = function(_, t)
	tip[#tip + 1] = "  " .. t
end
_G.GameTooltip_AddNormalLine = function(_, t)
	tip[#tip + 1] = "  " .. t
end
_G.GameTooltip_AddInstructionLine = function(_, t)
	tip[#tip + 1] = "  " .. t
end
_G.GameTooltip_AddColoredDoubleLine = function(_, l, r)
	tip[#tip + 1] = "  " .. l .. " | " .. r
end
_G.SlashCmdList = {}
_G.CreateFromMixins = function(...)
	local t = {}
	for _, m in ipairs({ ... }) do
		for k, v in pairs(m) do
			t[k] = v
		end
	end
	return t
end
_G.Mixin = function(t, ...)
	for _, m in ipairs({ ... }) do
		for k, v in pairs(m) do
			t[k] = v
		end
	end
	return t
end
