-- Model an owner repeatedly submitting the same short stop while the cold client pumps packed navigation.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
for _, file in ipairs({
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
	"UI/Looks.lua",
	"Core/APIInput.lua",
	"Core/APIStops.lua",
	"Core/API.lua",
	"Journey/Itinerary.lua",
}) do
	driver.load(file)
end
assert(loadfile("tools/load_nav.lua"))(0, nil, env, true)
local Path, Search = ns.Path, ns.JourneySearch
local clock, nextFrame = 0, nil
-- Charge each budget checkpoint so the work slices deterministically across frames.
Path.clock = function()
	clock = clock + 0.2
	return clock
end
Path.after = function(fn, seconds)
	if not seconds then
		assert(not nextFrame, "only one pump is due per frame")
		nextFrame = fn
	end
end
local from = { map = 0, x = -8849, y = 647.9 }
local x, y = -8832.8, 478.6
local worldPosition = env.C_Map.GetWorldPosFromMapPos
env.C_Map.GetWorldPosFromMapPos = function(_, point)
	return worldPosition(0, point)
end
local stop = { map = 1453, x = 0.5 - y / 50000, y = 0.5 - x / 50000, hold = true }
local API = env.ShortestPathForever.API
local function submit()
	assert(API.NavigateRoute("Guide", { stop }))
end
local starts, frames = 0, 0
local start = Search.Start
Search.Start = function(...)
	starts = starts + 1
	return start(...)
end

driver.move(from)
submit()
while nextFrame and frames < 600 do
	local pump = nextFrame
	nextFrame = nil
	pump()
	frames = frames + 1
	driver.update(1 / 51)
	if not ns.JourneyPlan() then
		submit()
	end
end
local pending, rounds = Search.Status()
print(
	("cold short route: %d frames, %d starts, %d decodes, %d settle rounds"):format(
		frames,
		starts,
		Path.decodes or 0,
		rounds
	)
)
assert(starts == 1, "an unchanged submission must not restart the cold search")
assert(not nextFrame and pending == 0, "the cold search settled")
local route = assert(ns.JourneyPlan(), "the short route was found")
assert(route.legs[1].measured and route.legs[1].mode == "walk", "the short walk is usable")
