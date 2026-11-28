-- Boot a client that lets a Shortest Path journey drive TomTom's arrow.
local Fake = assert(loadfile("tests/tomtom_fake.lua"))()

---@class SPFTomTomArrowTestOptions
---@field tomtomArrow? boolean
---@field tomtomFollow? boolean
---@field arrow? boolean
---@field installed? boolean
---@field withArrow? boolean
---@field restedXPBridge? boolean
---@field deferLogin? boolean
---@field savedWaypoints? table[]

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
	d.load("Core/APIInput.lua")
	d.load("Core/APIStops.lua")
	d.load("Core/API.lua")

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
	local function Schedule(delay, fn)
		timers[#timers + 1] = { at = e.GetTime() + delay, fn = fn }
	end
	e.C_Timer = {
		After = Schedule,
		NewTicker = function(period, fn, count)
			local ticker = {}
			function ticker:Cancel()
				self.cancelled = true
			end
			local function Tick()
				if not ticker.cancelled then
					fn(ticker)
					count = count and count - 1
					if count ~= 0 and not ticker.cancelled then
						Schedule(period, Tick)
					end
				end
			end
			Schedule(period, Tick)
			return ticker
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
	d.load("Journey/Itinerary.lua")

	local fake
	if hasTomTom then
		fake = Fake.New(opts.savedWaypoints, crazy, opts.restedXPBridge)
		function fake:ShowHideCrazyArrow()
			crazy:Show()
			crazy:SetAlpha(self.arrowAlpha or 0.7)
			crazy:EnableMouse(self.arrowMouse ~= false)
		end
		if opts.restedXPBridge then
			e.TomTom = fake
		end
	end
	d.load("Core/TomTom.lua")
	d.load("Core/TomTomArrow.lua")
	local function RunTimers()
		local due = timers
		timers = {}
		for _, timer in ipairs(due) do
			if timer.at <= e.GetTime() then
				timer.fn()
			else
				timers[#timers + 1] = timer
			end
		end
	end
	local position = n.JourneyPosition
	if restoredGuide or opts.restedXPBridge then
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
		local arrow = e.CreateFrame("Frame")
		arrow.element = restoredGuide and element or nil
		arrow.texture, arrow.text = Region(), Region()
		e.RXPG_ARROW = arrow
		e.RXP = {
			arrowFrame = arrow,
			settings = { profile = { showEnabled = true } },
			currentGuide = {},
			activeWaypoints = restoredGuide and { element } or {},
			UpdateMap = function() end,
			UpdateGotoSteps = function() end,
			DrawArrow = function() end,
		}
		local login = e.CreateFrame("Frame")
		login:RegisterEvent("PLAYER_ENTERING_WORLD")
		login:SetScript("OnEvent", function(_, event)
			if event == "PLAYER_ENTERING_WORLD" then
				e.RXP.UpdateMap()
			end
		end)
		n.db.restedxp = true
		n.JourneyPosition = function() end
		d.load("Core/RestedXP.lua")
	end
	local bridge = opts.restedXPBridge and Fake.Bridge(e) or nil

	-- Track any frame UI/Arrow.lua creates during guidance.
	local createdByArrow = e.CreateFrame
	e.CreateFrame = function(...)
		local f = createdByArrow(...)
		arrowFrame = arrowFrame or f
		return f
	end

	local function Login()
		if fake then
			if not e.TomTom then
				e.TomTom = fake
				d.fire("ADDON_LOADED", "TomTom")
			end
			fake:Enable()
		end
		d.fire("PLAYER_LOGIN")
	end
	local function World()
		d.move({ map = 1, x = 0, y = 0 })
		d.fire("PLAYER_ENTERING_WORLD")
		n.JourneyPosition = position
	end
	if not opts.deferLogin then
		Login()
		World()
		RunTimers()
	end
	return {
		driver = d,
		ns = n,
		env = e,
		API = e.ShortestPathForever.API,
		tomtom = fake,
		crazy = crazy,
		runTimers = RunTimers,
		login = Login,
		world = World,
		bridge = bridge,
		arrowFrame = function()
			return arrowFrame
		end,
	}
end
