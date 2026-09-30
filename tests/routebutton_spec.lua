-- The minimap route button: the game's own minimap button plate wearing the addon's icon, starting and
-- stopping the route through Journey's own Guide toggle rather than a route of its own, gold while a route is
-- on, and never built at all for a player who turned the setting off.
--
-- The toggle path here is Journey's, with UI/Tracker.lua's refresh paint modelled as one call; the end-to-end
-- journey, click and paint are in tests/routebutton_ui.lua.
local atlasSizes = { ["ui-hud-minimap-button"] = { width = 20, height = 18 } }

local function close(actual, expected, tolerance)
	assert(math.abs(actual - expected) < (tolerance or 1e-6), tostring(actual) .. " ~= " .. tostring(expected))
end

local function boot(options)
	local calls = { objects = 0, points = 0, atlases = 0, vertices = 0 }
	local handle = { calls = calls }
	local function noop() end
	local methods = {}
	local function object()
		calls.objects = calls.objects + 1
		return setmetatable({ scripts = {}, hidden = true }, { __index = methods })
	end
	function methods:SetPoint(point, owner, relativePoint, x, y)
		calls.points = calls.points + 1
		self.point, self.owner, self.relativePoint, self.x, self.y = point, owner, relativePoint, x, y
	end
	function methods.CreateTexture()
		return object()
	end
	function methods:SetSize(width, height)
		self.width, self.height = width, height
	end
	function methods:SetAtlas(atlas)
		assert(atlasSizes[atlas], "unverified atlas: " .. atlas)
		calls.atlases = calls.atlases + 1
		self.atlas, self.file = atlas, nil
	end
	function methods:SetTexture(file)
		self.file, self.atlas = file, nil
	end
	function methods.SetVertexColor(region, ...)
		calls.vertices = calls.vertices + 1
		region.vertex = { ... }
	end
	function methods:SetScript(name, fn)
		self.scripts[name] = fn
	end
	function methods:RegisterForClicks(...)
		self.clicks = { ... }
	end
	function methods:SetHighlightTexture(file, mode)
		self.highlight = { file, mode }
	end
	function methods:SetFrameStrata(strata)
		self.strata = strata
	end
	function methods:Show()
		self.hidden = false
	end
	function methods:Hide()
		self.hidden = true
	end
	function methods:IsShown()
		return not self.hidden
	end
	function methods:SetShown(shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end
	local state =
		{ guided = options.guided == true, journey = options.journey ~= false, toggles = 0, opened = 0, nearby = 0 }
	local ns
	ns = {
		db = { routeButton = options.routeButton ~= false },
		HasJourney = function()
			return state.journey
		end,
		IsJourneyGuided = function()
			return state.guided
		end,
		-- Journey's own toggle; its refresh runs through UI/Tracker.lua, which paints the button.
		ToggleJourneyGuide = function()
			state.toggles = state.toggles + 1
			state.guided = not state.guided
			ns.RefreshRouteButton()
		end,
		OpenNearby = function()
			state.nearby = state.nearby + 1
		end,
		OpenSettings = function()
			state.opened = state.opened + 1
		end,
		Init = function(fn)
			fn()
		end,
	}
	assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
	local minimap = {
		GetWidth = function()
			return 200
		end,
	}
	local tip = {}
	local env = setmetatable({
		Minimap = minimap,
		CreateFrame = function()
			handle.button = object()
			return handle.button
		end,
		C_Texture = {
			GetAtlasInfo = function(atlas)
				return assert(atlasSizes[atlas])
			end,
		},
		canaccessvalue = function()
			return true
		end,
		GameTooltip = { SetOwner = noop, Show = noop, Hide = noop },
		GameTooltip_SetTitle = function(_, title)
			for index = #tip, 1, -1 do
				tip[index] = nil
			end
			tip[1] = "# " .. title
		end,
		GameTooltip_AddInstructionLine = function(_, text)
			tip[#tip + 1] = "  " .. text
		end,
	}, { __index = _G })
	-- FitAtlas is UI/Looks.lua's, so the plate is fitted the way the addon fits every atlas.
	setfenv(assert(loadfile("UI/Looks.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/RouteButton.lua")), env)("ShortestPathForever", ns)
	handle.ns, handle.minimap, handle.tip, handle.state = ns, minimap, tip, state
	return handle
end

local neutral = { 1, 1, 1 }
local gold = { 1, 0.82, 0 }

-- The default: one button, the game's plate at its native shape, the addon's icon inside it.
local run = boot({})
assert(run.calls.objects == 3, "the frame, its plate and its icon: " .. run.calls.objects)
local button = assert(run.button, "the default setting builds the button")
assert(not button.hidden, "shown while the setting is on")
close(button.Plate.width, 20, 1e-9)
close(button.Plate.height, 18, 1e-9)
assert(button.owner == run.minimap and button.point == "CENTER", "the button is anchored to the minimap")
assert(button.Plate.point == "CENTER", "the plate is centred in it")
assert(button.Icon.file == "Interface\\AddOns\\ShortestPathForever\\media\\Icon", button.Icon.file)
assert(button.Icon.atlas == nil, "the addon's own icon, not an atlas")
close(button.Icon.width / button.Icon.height, 1, 1e-9)
assert(button.width == 24 and button.height == 24, "a button-sized hit area over it")
assert(button.strata == "MEDIUM")
assert(button.clicks[1] == "LeftButtonUp" and button.clicks[2] == "RightButtonUp", "both mouse buttons")
assert(button.highlight[1] == "Interface\\Buttons\\UI-Common-MouseHilight" and button.highlight[2] == "ADD")
assert(button.Plate.atlas == "ui-hud-minimap-button", button.Plate.atlas)
-- 315 degrees round the minimap from its right edge: the lower right, 6 yards past its rim.
local radius = 200 / 2 + 6
close(button.x, math.cos(math.rad(315)) * radius)
close(button.y, math.sin(math.rad(315)) * radius)
for index = 1, 3 do
	close(button.Plate.vertex[index], neutral[index])
end
close(run.calls.vertices, 1, 1e-9)

-- A route on turns the plate the game's gold; nothing changed means nothing written, frame after frame.
run.state.guided = true
run.ns.RefreshRouteButton()
for index = 1, 3 do
	close(button.Plate.vertex[index], gold[index])
end
local vertices = run.calls.vertices
for _ = 1, 30 do
	run.ns.RefreshRouteButton()
end
assert(run.calls.vertices == vertices and run.calls.points == run.calls.points, "an unchanged route writes nothing")

-- The click is Journey's own toggle, so the button never becomes a second owner of the route.
button.scripts.OnClick(button, "LeftButton")
assert(run.state.toggles == 1, "one toggle per left click")
assert(not run.state.guided, "the click stopped the route")
close(button.Plate.vertex[2], 1)
button.scripts.OnClick(button, "LeftButton")
assert(run.state.toggles == 2 and run.state.guided, "and started it again")
close(button.Plate.vertex[2], 0.82)

-- Right-click opens the addon's settings category instead of touching the route.
button.scripts.OnClick(button, "MiddleButton")
assert(run.state.nearby == 1, "middle-click opens nearby services")
assert(run.state.toggles == 2 and run.state.opened == 0, "service click only opens the finder")
button.scripts.OnClick(button, "RightButton")
assert(run.state.opened == 1 and run.state.toggles == 2, "right-click leaves the route alone")

-- The tooltip says what the click will do, and what to do when there is no route yet.
run.state.journey, run.state.guided = false, false
button.scripts.OnEnter(button)
assert(run.tip[1] == "# Route", run.tip[1])
assert(run.tip[2] == "  Shift-click the world map or minimap to plan one.", run.tip[2])
run.state.journey, run.state.guided = true, true
button.scripts.OnEnter(button)
assert(run.tip[2] == "  The route is on. Click to stop.", run.tip[2])
run.state.guided = false
button.scripts.OnEnter(button)
assert(run.tip[2] == "  Click to start the route.", run.tip[2])
button.scripts.OnLeave(button)

-- The setting off hides the button, and an install that never had it on never builds the frame.
run.ns.db.routeButton = false
run.ns.RefreshRouteButton()
assert(button.hidden and run.calls.objects == 3, "hiding keeps the frame it already has")
run.ns.db.routeButton = true
run.ns.RefreshRouteButton()
assert(not button.hidden, "turning it back on shows the same button")
local off = boot({ routeButton = false })
assert(off.calls.objects == 0 and off.button == nil, "the setting off builds nothing")

print("route button: the game's plate, the addon's icon, one route owner, the gold state and the setting: ok")
