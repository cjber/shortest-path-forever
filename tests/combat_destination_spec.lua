-- A map click in combat queues the latest destination and says so on screen; the path pump waits for regen.
if not os.getenv("SPF_BLIZZARD_UI") then
	local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
	assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture")
end

local function read(path)
	local file = assert(io.open(path))
	local source = file:read("*a")
	file:close()
	return source
end

assert(loadstring(read("tests/ui_client.lua") .. read("tests/ui_map.lua") .. [[
local fixture = dofile("tests/nav_fixture.lua")
local cells = {}
for x = 8, 55 do
	cells[x] = {}
	for y = 8, 55 do
		cells[x][y] = { z = 0 }
	end
end
fixture.install(1, fixture.format1_cells({ nx = 1, ny = 1, cell = cells }))
ns.Path = actualPath
local nextFrame
actualPath.after = function(fn, seconds)
	if not seconds then
		nextFrame = fn
	end
end
local function pump()
	for _ = 1, 100 do
		if not nextFrame then
			return
		end
		local fn = nextFrame
		nextFrame = nil
		fn()
	end
	error("path pump did not settle")
end

local notices = {}
UIErrorsFrame = {
	AddMessage = function(_, message)
		notices[#notices + 1] = message
	end,
}

local function confirmations()
	local count = 0
	for _, message in ipairs(notices) do
		if message == "Destination queued until combat ends." then
			count = count + 1
		end
	end
	return count
end

ns.Print = function() error("the queued destination used chat") end
posX, posY, posZ, posMap = 84, 84, 0, 1
zoom = 1
setMapShown(true)
fireEvent("PLAYER_REGEN_DISABLED")
combat = true
cursorX, cursorY = 0.48768, 0.48768
assert(clickHandlers[1](map, "LeftButton"))
local first = assert(ns.JourneyGoal(), "the first click is accepted in combat")
cursorX, cursorY = 0.48352, 0.48352
assert(clickHandlers[1](map, "LeftButton"))
local latest = assert(ns.JourneyGoal(), "the second click is accepted in combat")
assert(latest.x > first.x and latest.y > first.y, "the latest click replaces the first destination")
pump()
assert(not ns.JourneyPlan() and actualPath.work.frames == 0, "the path pump sleeps during lockdown")
assert(confirmations() == 2, "each pick mid-fight is confirmed on screen")
-- A guide moving its own objective is not a pick: it queues silently.
ns.RetargetJourney({ map = latest.map, x = latest.x, y = latest.y, label = latest.label })
assert(confirmations() == 2, "a retarget in combat says nothing")
-- A single Nearby place: the public calls refuse mid-fight, the player's pick is taken.
local at = assert(ns.Locate(latest))
local stop = { map = at.uiMap, x = at.x + 0.002, y = at.y, title = "Innkeeper", kind = "innkeeper" }
assert(ShortestPathForever.API.Navigate("Some Guide", stop.map, stop.x, stop.y) == false, "refused to addons")
assert(ns.PickInCombat(stop) == true, "the Nearby pick is accepted in combat")
latest = assert(ns.JourneyGoal())
assert(latest.label == "Innkeeper" and confirmations() == 3, "the Nearby pick is queued and confirmed")

combat = false
fireEvent("PLAYER_REGEN_ENABLED")
pump()
local plan = assert(ns.JourneyPlan(), "ending combat plots the queued journey")
local endpoint = plan.legs[#plan.legs].to
assert(endpoint.x == latest.x and endpoint.y == latest.y, "the plan reaches the latest destination")
local route = active.ShortestPathForeverRoutePinTemplate[1]
assert(route and route:IsVisible() and route.used > 0, "the route is painted when the search resumes")
cursorX, cursorY = 0.48768, 0.48768
assert(clickHandlers[1](map, "LeftButton"))
assert(confirmations() == 3, "a pick out of combat is not queued")
-- A pick mid-fight replacing a plotted one drops the old line: the new search only settles after the fight.
local function pick(offset)
	local to = { map = stop.map, x = stop.x + offset, y = stop.y, title = "Vendor", kind = "vendor" }
	assert(ns.PickInCombat(to) == true)
end
fireEvent("PLAYER_REGEN_DISABLED")
combat = true
pick(0)
combat = false
fireEvent("PLAYER_REGEN_ENABLED")
pump()
assert(ns.JourneyPlan(), "the pick is plotted before the fight")
fireEvent("PLAYER_REGEN_DISABLED")
combat = true
pick(0.002)
mapTick()
assert(not ns.JourneyPlan(), "the replaced destination's plan is dropped")
assert(not (route:IsVisible() and route.used > 0), "and so is its line")
combat = false
fireEvent("PLAYER_REGEN_ENABLED")
pump()
assert(#errors == 0, table.concat(errors, "\n"))
print("combat_destination_spec: destination accepted, confirmed and plotted after combat")
]], "@combat_destination_spec"))()
