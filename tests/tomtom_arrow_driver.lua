-- Boot a client that lets a Shortest Path journey drive TomTom's arrow.
local Fake = assert(loadfile("tests/tomtom_fake.lua"))()

---@class SPFTomTomArrowTestOptions
---@field tomtomArrow? boolean
---@field tomtomFollow? boolean
---@field arrow? boolean
---@field installed? boolean
---@field withArrow? boolean
---@field restedXPBridge? boolean

---@param opts SPFTomTomArrowTestOptions
---@param restoredGuide? boolean
return function(opts, restoredGuide)
	local d = assert(loadfile("tests/journey_driver.lua"))()
	local n, e = d.ns, d.env
	local arrowFrame
	local baseCreate = e.CreateFrame
	e.CreateFrame = function(...)
		local f = baseCreate(...)
		f.SetShown = function(self, shown)
			if shown then
				self:Show()
			else
				self:Hide()
			end
		end
		f.EnableMouse = function(self, enabled)
			self.mouse = enabled
		end
		f.IsMouseEnabled = function(self)
			return self.mouse == true
		end
		f.SetScale = function(self, scale)
			self.scale = scale
		end
		f.GetCenter = function()
			return 500, 500
		end
		return f
	end
	d.load("UI/Looks.lua")
	if opts.withArrow ~= false then
		d.load("UI/Art.lua")
		d.load("UI/Mover.lua")
		d.load("UI/TurnAround.lua")
		d.load("UI/CastButton.lua")
		d.load("UI/Arrow.lua")
	end
	-- Capture the arrow frame lazily when UI/Arrow.lua creates it.
	local arrowCreate = e.CreateFrame
	local watcherFrame
	e.CreateFrame = function(...)
		local f = arrowCreate(...)
		watcherFrame = f
		return f
	end
	d.load("Core/APIInput.lua")
	d.load("Core/APIStops.lua")
	d.load("Core/API.lua")
	d.load("Journey/Itinerary.lua")

	local crazy = { alpha = 0.7, mouse = true, hidden = true }
	function crazy:SetAlpha(v)
		self.alpha = v
	end
	function crazy:EnableMouse(v)
		self.mouse = v
	end
	function crazy:Show()
		self.hidden = false
	end
	function crazy:Hide()
		self.hidden = true
	end
	e.TomTomCrazyArrow = crazy

	local timers = {}
	e.C_Timer = {
		After = function(_, fn)
			timers[#timers + 1] = fn
		end,
		NewTicker = function()
			return { Cancel = function() end }
		end,
	}
	e.InCombatLockdown = function()
		return false
	end
	e.C_Item = e.C_Item
		or {
			GetItemNameByID = function()
				return "Hearthstone"
			end,
			GetItemIconByID = function()
				return 134414
			end,
		}
	e.UnitName = function()
		return "Tester"
	end
	e.UnitGUID = function()
		return "Player-1-TESTER"
	end
	e.hooksecurefunc = function(target, key, hook)
		local original = target[key]
		target[key] = function(...)
			local result = original(...)
			hook(...)
			return result
		end
	end
	local hasTomTom = opts.installed ~= false
	e.C_AddOns = {
		DoesAddOnExist = function(name)
			return hasTomTom and name == "TomTom"
		end,
		IsAddOnLoaded = function(name)
			return (hasTomTom and name == "TomTom" and e.TomTom ~= nil)
				or (name == "RestedXP-TomTom" and opts.restedXPBridge == true)
		end,
		GetAddOnEnableState = function(name)
			return hasTomTom and name == "TomTom" and 2 or 0
		end,
	}
	n.db.tomtom = true
	n.db.tomtomFollow = opts.tomtomFollow == true
	n.db.tomtomArrow = opts.tomtomArrow == true
	n.db.arrow = opts.arrow ~= false

	d.load("Core/TomTom.lua")
	local tomtomWatcher = watcherFrame
	d.load("Core/TomTomArrow.lua")

	-- Track any frame UI/Arrow.lua creates after load.
	local createdByArrow = e.CreateFrame
	e.CreateFrame = function(...)
		local f = createdByArrow(...)
		arrowFrame = arrowFrame or f
		return f
	end

	local fake
	if hasTomTom then
		fake = Fake.New(nil, crazy, opts.restedXPBridge)
		function fake:ShowHideCrazyArrow()
			crazy:Show()
			crazy:SetAlpha(self.arrowAlpha or 0.7)
			crazy:EnableMouse(self.arrowMouse ~= false)
		end
		e.TomTom = fake
		tomtomWatcher:OnEvent("ADDON_LOADED", "TomTom")
		fake:Enable()
	end
	local function RunTimers()
		local due = timers
		timers = {}
		for _, fn in ipairs(due) do
			fn()
		end
	end
	-- RestedXP-TomTom 1.5.2 selects only its own waypoints. A foreign selection pauses it until no foreign
	-- waypoints remain, even across step changes. The tests drive its ticks directly.
	local bridgeStep
	if opts.restedXPBridge then
		local waypoint
		local paused = false
		e.hooksecurefunc(fake, "SetCrazyArrow", function(_, uid)
			if uid ~= waypoint then
				paused = true
			end
		end)
		bridgeStep = function(index)
			if waypoint then
				fake:RemoveWaypoint(waypoint)
			end
			waypoint = fake:AddWaypoint(1, 0.5 + index / 20, 0.5, {
				title = "RXP Step " .. index,
				source = "RXPGuides",
				crazy = false,
				persistent = false,
			})
			if not paused then
				fake:SetCrazyArrow(waypoint, 15, waypoint.title)
			end
			return waypoint
		end
	end
	if restoredGuide then
		local function Region()
			return {
				IsShown = function()
					return true
				end,
				Hide = function() end,
				SetShown = function() end,
			}
		end
		local element = { zone = 1, x = 60, y = 50, title = "RXP Step 1", arrow = true, step = { active = true } }
		e.RXP = {
			arrowFrame = { element = element, texture = Region(), text = Region() },
			settings = { profile = { showEnabled = true } },
			currentGuide = {},
			activeWaypoints = { element },
			UpdateMap = function() end,
			UpdateGotoSteps = function() end,
		}
		n.db.restedxp = true
		local position = n.JourneyPosition
		n.JourneyPosition = function() end
		local create = e.CreateFrame
		e.CreateFrame = function(...)
			watcherFrame = arrowCreate(...)
			return watcherFrame
		end
		d.load("Core/RestedXP.lua")
		e.CreateFrame = create
		n.JourneyPosition = position
		d.move({ map = 1, x = 0, y = 0 })
		watcherFrame:OnEvent("PLAYER_ENTERING_WORLD")
	end
	tomtomWatcher:OnEvent("PLAYER_ENTERING_WORLD")
	RunTimers()
	return {
		driver = d,
		ns = n,
		env = e,
		API = e.ShortestPathForever.API,
		tomtom = fake,
		crazy = crazy,
		runTimers = RunTimers,
		bridgeStep = bridgeStep,
		arrowFrame = function()
			return arrowFrame
		end,
	}
end
