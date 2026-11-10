local now, loaded, stitched = 0, {}, false
local pinScale = 1
C_AddOns = {
	IsAddOnLoaded = function(name)
		return loaded[name] == true
	end,
}
GetTime = function()
	return now
end
local plan
local ns = {
	JourneyPlan = function()
		return plan, 1
	end,
	OpenMapAddon = {
		Stitched = function()
			return stitched
		end,
	},
}
assert(loadfile("UI/CompanionMaps.lua"))("ShortestPathForever", ns)
local children = {}
local siblingPins = {}
local scroll = {
	GetChildren = function()
		return unpack(siblingPins)
	end,
}
local canvas = {
	GetParent = function()
		return scroll
	end,
	GetWidth = function()
		return 1000
	end,
	GetHeight = function()
		return 1000
	end,
	GetEffectiveScale = function()
		return 1
	end,
	GetLeft = function()
		return 0
	end,
	GetTop = function()
		return 1000
	end,
	GetChildren = function()
		return unpack(children)
	end,
}
local map = {
	GetCanvas = function()
		return canvas
	end,
}
local function scan()
	now = now + 1
	return ns.CompanionMaps.Scan(map)
end
local pin = {
	isLeaMapsPin = true,
	data = { "FlightA" },
	shown = true,
	IsVisible = function(self)
		return self.shown
	end,
	GetEffectiveScale = function()
		return pinScale
	end,
	GetCenter = function()
		return 500 / pinScale, 500 / pinScale
	end,
	GetChildren = function() end,
}
children[1] = pin
scan()
assert(not ns.CompanionMaps.Suppresses("flight", 0.5, 0.5), "unloaded addons do not suppress")
loaded.Leatrix_Maps = true
local signature = scan()
assert(ns.CompanionMaps.Suppresses("flight", 0.5, 0.5))
assert(not ns.CompanionMaps.Suppresses("flight", 0.7, 0.5), "uncovered destinations remain")
assert(not ns.CompanionMaps.Suppresses("portal", 0.5, 0.5), "categories do not overlap")
pinScale = 0.7
scan()
assert(ns.CompanionMaps.Suppresses("flight", 0.5, 0.5), "pin scale is converted into canvas units")
local previous = scan()
plan = { legs = { { from = { kind = "taxi", id = 9 }, to = { kind = "goal" } } } }
assert(not ns.CompanionMaps.Suppresses("flight", 0.5, 0.5, "taxi", 9), "journey transport stop keeps SPF interaction")
assert(scan() ~= previous, "journey changes invalidate layers while map stays open")
plan = nil
pin.shown = false
assert(scan() ~= signature and not ns.CompanionMaps.Suppresses("flight", 0.5, 0.5), "hidden companion restores SPF")
pin.shown, pin.data = true, { "TravelN" }
scan()
assert(ns.CompanionMaps.Suppresses("tram", 0.5, 0.5))
assert(not ns.CompanionMaps.Suppresses("lift", 0.5, 0.5))
loaded.Leatrix_Maps, loaded.OpenMap = false, true
pin.isLeaMapsPin, pin.u, pin.v, pin.look, pin.node = false, 0.5, 0.5, {}, 1
scan()
assert(not ns.CompanionMaps.Suppresses("flight", 0.5, 0.5), "OpenMap requires stitched art")
stitched = true
children[1] = nil
siblingPins[1] = pin
scan()
assert(ns.CompanionMaps.Suppresses("flight", 0.5, 0.5))
pin.shown = false
scan()
assert(not ns.CompanionMaps.Suppresses("flight", 0.5, 0.5), "zoom-hidden OpenMap pins do not suppress")
print("companion_maps_spec: visible coverage, categories, unload and zoom passed")
