-- Reaching a held stop's area turns the direction arrow into the client's own waypoint pin with the stop's
-- objectives under it (#627), instead of hiding; leaving the area or changing the stop brings the arrow back, and
-- turning the setting off keeps the old hide.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local create = env.CreateFrame
local created = {}

local function track(object)
	object.GetText = function(self)
		return self.text
	end
	object.SetText = function(self, text)
		self.text = text
	end
	object.Show = function(self)
		self.hidden = false
	end
	object.Hide = function(self)
		self.hidden = true
	end
	object.SetShown = function(self, shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end
	object.SetAtlas = function(self, atlas)
		self.atlas = atlas
	end
	object.SetTexture = function(self, file)
		self.texture, self.atlas = file, nil
	end
	object.SetTexCoord = function() end
	object.SetSize = function(self, width, height)
		self.width, self.height = width, height
	end
	object.SetPoint = function(self, ...)
		self.point = { ... }
	end
	object.SetWordWrap = function(self, wrap)
		self.wrap = wrap
	end
	object.SetMaxLines = function(self, lines)
		self.maxLines = lines
	end
	object.SetJustifyH = function(self, justify)
		self.justify = justify
	end
	object.SetColorTexture = function(self, ...)
		self.color = { ... }
	end
	object.SetAlpha = function(self, alpha)
		self.alpha = alpha
	end
	object.GetEffectiveScale = function()
		return 1
	end
	object.SetScale = function(self, scale)
		self.scale = scale
	end
	return object
end

env.CreateFrame = function(...)
	local frame = track(create(...))
	created[#created + 1] = frame
	local texture, font = frame.CreateTexture, frame.CreateFontString
	frame.CreateTexture = function(self, ...)
		return track(texture(self, ...))
	end
	frame.CreateFontString = function(self, ...)
		return track(font(self, ...))
	end
	-- The client runs OnShow/OnHide as a frame becomes visible or hidden; the driver's mock does not.
	local show, hide = frame.Show, frame.Hide
	frame.Show = function(self)
		local wasHidden = self.hidden
		show(self)
		if wasHidden and self.OnShow then
			self.OnShow(self)
		end
	end
	frame.Hide = function(self)
		local wasShown = not self.hidden
		hide(self)
		if wasShown and self.OnHide then
			self.OnHide(self)
		end
	end
	return frame
end
env.C_Timer = {
	NewTicker = function(_, fn)
		local ticker = { fn = fn }
		function ticker:Cancel()
			self.cancelled = true
		end
		return ticker
	end,
	After = function(_, fn)
		fn()
	end,
}
env.C_Texture = {
	GetAtlasInfo = function(atlas)
		if atlas == "Waypoint-MapPin-Tracked" then
			return { width = 30, height = 30 }
		end
	end,
}
for _, file in ipairs({ "UI/Art.lua", "UI/Mover.lua", "UI/TurnAround.lua", "UI/Arrow.lua" }) do
	driver.load(file)
end
ns.db.arrow, ns.db.arrivalPin, ns.db.guideStops = true, true, true

local function arrowFrame()
	for _, frame in ipairs(created) do
		if frame.ArrivalTitle then
			return frame
		end
	end
end

local stop = {
	map = 1,
	x = 0,
	y = 0,
	hold = true,
	radius = 50,
	label = "The Camp",
	routeTitle = "Stop 1 of 2: The Camp",
	details = { "Slay 6 boars", "Collect 4 tusks", "Return to the camp" },
}
driver.move({ map = 1, x = 1000, y = 0, z = 0 })
assert(ns.StartJourney(stop))
driver.path.settle()
local frame = assert(arrowFrame(), "the journey's arrow is built")
assert(not ns.ArrivalStop() and frame.Icon.texture == ns.PIN_FILE, "on the way, it is still the direction arrow")

-- Standing in the stop's area: the pin, the title and the objective lines, capped at a few.
driver.move({ map = 1, x = 0, y = 0, z = 0 })
driver.update(0.1)
assert(ns.ArrivalStop() == stop, "the stop whose area the player is in is the arrival")
assert(frame.arrival and not frame.hidden, "the arrow frame stays up as the arrival pin")
assert(frame.Icon.atlas == "Waypoint-MapPin-Tracked", "the client's own pin art")
assert(frame.Icon.width == 36 and frame.Icon.height == 36, "drawn at the pin's native square aspect")
assert(frame.ArrivalTitle.text == "Stop 1 of 2: The Camp", "the stop's title beneath it")
assert(
	frame.ArrivalLines.text == "Slay 6 boars\nCollect 4 tusks\nReturn to the camp",
	"the stop's objective lines beneath it"
)
assert(frame.ArrivalLines.maxLines == 3 and frame.ArrivalLines.wrap == true, "wrapped and capped at a few lines")
assert(frame.Arrow.hidden and frame.Distance.hidden and frame.Progress.hidden, "the arrow and its distance stand down")

-- Leaving the area: the journey takes the arrow back.
driver.move({ map = 1, x = 1000, y = 0, z = 0 })
driver.update(0.1)
assert(not ns.ArrivalStop() and not frame.arrival, "leaving the area ends the arrival")
assert(frame.Icon.texture == ns.PIN_FILE and not frame.Arrow.hidden, "and the direction arrow returns")

-- Coming back shows it again; a new stop then replaces it with the arrow.
driver.move({ map = 1, x = 0, y = 0, z = 0 })
driver.update(0.1)
assert(ns.ArrivalStop() == stop, "walking back into the area shows the arrival pin again")
assert(ns.StartJourney({ map = 1, x = 500, y = 0, hold = true, radius = 50, label = "Elsewhere" }))
driver.path.settle()
assert(not ns.ArrivalStop() and not frame.arrival, "a new stop ends the arrival")
assert(frame.Icon.texture == ns.PIN_FILE and not frame.Arrow.hidden, "with the arrow leading to the new stop")

-- Back in the area, turning the setting off gives the old hide at once, without waiting to leave.
driver.move({ map = 1, x = 500, y = 0, z = 0 })
driver.update(0.1)
assert(ns.ArrivalStop(), "the new stop's area shows the pin first")
ns.db.arrivalPin = false
ns.JourneyGuide.Pause()
assert(not ns.ArrivalStop() and frame.hidden, "with the setting off, arrival hides as it did before")
assert(ns.StartJourney({ map = 1, x = 1000, y = 0, hold = true, radius = 50, label = "Quiet" }))
driver.path.settle()
assert(not frame.hidden and frame.Icon.texture == ns.PIN_FILE, "the arrow leads to the next stop")
driver.move({ map = 1, x = 1000, y = 0, z = 0 })
driver.update(0.1)
assert(not ns.ArrivalStop() and frame.hidden, "arriving with the setting off still hides the arrow")
print("arrival_pin_spec: pin with objectives on arrival, arrow back on leaving or a new stop, old hide when off")
