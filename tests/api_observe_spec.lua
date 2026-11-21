-- NavigateRoute's options, JourneyState and ObserveStops: what a consumer driving its own route reads, through the real
-- journey, planner and API.
local d = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = d.ns, d.env, 0
d.load("UI/Looks.lua")
d.load("Core/APIInput.lua")
d.load("Core/APIStops.lua")
d.load("Core/API.lua")
d.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API
local function check(value, label)
	checks = checks + 1
	assert(value, label)
end
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function point(x)
	return { map = 1, x = x, y = 0 }
end
local function stop(x, title)
	return { map = 1, x = 0.5, y = 0.5 - x / 50000, title = title }
end
local combat = false
env.InCombatLockdown = function()
	return combat
end

-- Options: nil, {} and the two policies are accepted; anything else is nil and "invalid" and changes nothing.
for _, options in ipairs({
	"walking",
	5,
	{ policy = "fast" },
	{ policy = 7 },
	{ speed = 1 },
	{ policy = "walking", x = 1 },
}) do
	local ok, reason = API.NavigateRoute("o", { stop(1000) }, options)
	equal(ok, nil, "invalid options answer nil")
	equal(reason, "invalid", "invalid options answer invalid")
end
equal(API.CurrentStop("o"), nil, "an invalid options call starts nothing")
local inherited = setmetatable({}, {
	__index = function()
		error("options must only read submitted keys")
	end,
})
check(API.NavigateRoute("o", { stop(1000) }, inherited), "an empty options table uses the default")
check(API.NavigateRoute("o", { stop(1000) }, {}), "empty options")
check(API.NavigateRoute("o", { stop(1000) }, { policy = "normal" }), "normal policy")
check(API.NavigateRoute("o", { stop(1000), stop(2000) }, { policy = "walking" }), "walking policy")
equal(API.JourneyState().policy, "walking", "the state names the route's policy")
equal(API.NavigateRoute("o", { { map = 0 } }, { policy = "walking" }), false, "a bad stop is still false")
check(API.Cancel("o"), "cancel")
d.path.settle()

-- JourneyState: nothing under way.
local state = API.JourneyState()
equal(state.busy, false, "idle is not busy")
equal(state.owner, nil, "idle has no owner")
equal(state.policy, "normal", "idle policy")
equal(#state.legs, 0, "idle has no legs")
equal(state.blocked, nil, "idle is not blocked")
equal(state.failure, nil, "idle has no failure")

-- A route still working, then settled.
d.path.auto = false
check(API.NavigateRoute("o", { stop(1000), stop(3000) }, { policy = "walking" }), "walking route")
state = API.JourneyState()
equal(state.busy, true, "a route is busy")
equal(state.owner, "o", "the route's owner")
equal(state.pending, true, "the search is pending")
d.path.auto = true
d.path.settle()
state = API.JourneyState()
equal(state.pending, false, "settled")
equal(state.settling, false, "no first search running")
equal(state.failure, nil, "no failure")
check(#state.legs > 0 and state.index == 1, "the plan's legs")
for _, leg in ipairs(state.legs) do
	equal(leg.mode, "walk", "a walking plan walks")
	equal(leg.measured, true, "and is measured")
end
check(state.distance and state.distance > 900 and state.reach == 15, "distance to the stop under way and the reach")
local copy = API.JourneyState()
copy.legs[1].mode = "boat"
equal(API.JourneyState().legs[1].mode, "walk", "every read is a fresh copy")

-- Blocked by combat or a corpse run.
combat = true
equal(API.JourneyState().blocked, "combat", "combat blocks")
combat = false
ns.Corpse = {
	Active = function()
		return true
	end,
}
equal(API.JourneyState().blocked, "corpse", "a corpse run blocks")
equal(API.JourneyState().owner, "o", "the route's owner is kept behind a corpse run")
ns.Corpse = nil
API.Cancel("o")
d.path.settle()

-- A walk that could not be measured is the failure, with its reason.
d.path.auto = false
check(API.NavigateRoute("o", { stop(5000) }, { policy = "walking" }), "route to fail")
for _, batch in ipairs(d.path.waiting(d.path.batches)) do
	d.path.costs(batch, false, "unreachable")
end
for _, job in ipairs(d.path.waiting(d.path.finds)) do
	d.path.finish(job, nil, "unreachable")
end
equal(API.JourneyState().failure, "unreachable", "the failure's reason")
d.path.auto = true
API.Cancel("o")
d.path.settle()

-- ObserveStops: refusals, then owner-scoped synchronous calls.
local function refuses(...)
	local unsubscribe, reason = API.ObserveStops(...)
	equal(unsubscribe, nil, "refused")
	equal(reason, "invalid", "refused reason")
end
refuses(nil, function() end)
refuses("o", 5)
refuses("o")
local heard, others = {}, {}
local unsubscribe = API.ObserveStops("o", function(phase, index, at, seen)
	heard[#heard + 1] = { phase = phase, index = index, at = at, state = seen }
	at.x = 0
end)
local unsubscribeOther = API.ObserveStops("other", function(phase)
	others[#others + 1] = phase
end)
check(API.NavigateRoute("o", { stop(1000, "first"), stop(3000, "second") }, { policy = "walking" }), "observed route")
d.path.settle()
check(#heard > 0 and heard[1].phase == "settled" and heard[1].index == 1, "settled is heard for the first stop")
equal(heard[1].at.title, "first", "the stop's title")
check(heard[1].at.map == 1 and heard[1].at.y ~= nil, "the stop is a place")
equal(heard[1].state.owner, "o", "the state is passed in")
equal(#others, 0, "another owner hears nothing")
heard = {}
d.move(point(1000))
d.update(1)
local arrived
for _, event in ipairs(heard) do
	if event.phase == "arrived" then
		arrived = event
	end
end
check(arrived and arrived.index == 1, "arrival at the first stop")
check(arrived.state.distance <= arrived.state.reach, "within reach at arrival")
equal(arrived.state.owner, "o", "the arrival's state")
equal(API.CurrentStop("o"), 2, "on to the second stop")
unsubscribe()
unsubscribe()
heard = {}
d.move(point(3000))
d.update(1)
equal(#heard, 0, "unsubscribed")
equal(#others, 0, "another owner still hears nothing")
unsubscribeOther()

-- Planning to an instance door and entering it both notify observers about the submitted stop.
do
	d.move(point(0))
	local instance = 0
	local getInstanceInfo, getRealZoneText, entrances = env.GetInstanceInfo, env.GetRealZoneText, ns.Entrances
	env.GetInstanceInfo = function()
		return "", "none", 0, "", 0, 0, false, instance
	end
	env.GetRealZoneText = function()
		return "Deadmines"
	end
	ns.Entrances = { [36] = { name = "Deadmines", map = 1, x = 3000, y = 0 } }
	local phases = {}
	local unsubscribeDungeon = API.ObserveStops("o", function(phase, index, seen)
		phases[phase] = { index = index, stop = seen }
	end)
	check(API.NavigateRoute("o", { { map = 36, x = 0.5, y = 0.5, title = "Boss" } }), "route into a dungeon")
	d.path.settle()
	check(phases.settled, "the instance stop notifies on settlement")
	d.move(point(3000))
	d.update(1)
	equal(phases.arrived, nil, "standing at the door does not notify arrival")
	instance = 36
	d.fire("PLAYER_ENTERING_WORLD")
	check(phases.arrived, "the instance stop notifies on entry")
	for _, phase in ipairs({ "settled", "arrived" }) do
		local event = phases[phase]
		equal(event.index, 1, "the instance stop's route index")
		equal(event.stop.map, 36, "the observed place is inside the instance")
		equal(event.stop.title, "Boss", "the observed title is the submitted title")
	end
	equal(API.Ended("o"), "arrived", "the instance route completed")
	unsubscribeDungeon()
	env.GetInstanceInfo, env.GetRealZoneText, ns.Entrances = getInstanceInfo, getRealZoneText, entrances
end

-- An observer may cancel the route it hears the arrival of: nothing runs on for that stop, and no error is raised.
do
	d.move(point(0))
	local cancelled = {}
	local stopObserving = API.ObserveStops("o", function(phase)
		if phase == "arrived" then
			cancelled[#cancelled + 1] = API.Cancel("o")
		end
	end)
	check(API.NavigateRoute("o", { stop(1000) }, { policy = "walking" }), "route to cancel on arrival")
	d.path.settle()
	d.move(point(1000))
	d.update(1)
	check(cancelled[1] == true, "the observer cancelled")
	equal(API.Ended("o"), "cancelled", "the route ended as cancelled")
	stopObserving()
end
-- An observer handing the stop to another owner leaves that owner's route running; observers get their own copies.
do
	d.move(point(0))
	local seenBy = {}
	local first = API.ObserveStops("o", function(phase, _, seen, st)
		if phase == "arrived" then
			seen.x, st.owner = -1, "changed"
			check(API.NavigateRoute("new", { stop(1000) }, { policy = "walking" }), "handed to another owner")
		end
	end)
	local second = API.ObserveStops("o", function(phase, _, seen, st)
		seenBy[#seenBy + 1] = { phase, seen.x, st.owner }
	end)
	check(API.NavigateRoute("o", { stop(1000) }, { policy = "walking" }), "route to hand over")
	d.path.settle()
	d.move(point(1000))
	d.update(1)
	equal(API.JourneyState().owner, "new", "the new owner's route runs on")
	check(API.Ended("new") == nil, "and has not ended")
	check(#seenBy == 0 or seenBy[#seenBy][2] ~= -1, "an observer cannot change what another sees")
	first()
	second()
	API.Cancel("new")
end
-- A handover during settlement leaves the new owner to process its own arrival on the next driver step.
do
	d.move(point(0))
	local handed
	local unsubscribeSettled = API.ObserveStops("o", function(phase)
		if phase == "settled" then
			handed = API.NavigateRoute("new", { stop(1000) }, { policy = "walking" })
		end
	end)
	d.path.auto = false
	check(API.NavigateRoute("o", { stop(1000) }, { policy = "walking" }), "route to hand over at settlement")
	d.move(point(1000))
	d.path.auto = true
	d.path.settle()
	check(handed, "the settlement observer handed over the route")
	equal(API.CurrentStop("new"), 1, "the old settlement did not arrive for the new owner")
	d.update(1)
	equal(API.Ended("new"), "arrived", "the new owner arrived on its own driver step")
	unsubscribeSettled()
end

-- The submitted coordinates still identify an untitled stop when reverse projection is unavailable.
do
	d.move(point(0))
	local projection = env.C_Map.GetMapPosFromWorldPos
	env.C_Map.GetMapPosFromWorldPos = function() end
	local observed
	local unsubscribeFallback = API.ObserveStops("o", function(_, _, seen)
		observed = seen
	end)
	check(API.NavigateRoute("o", { stop(1000) }, { policy = "walking" }), "route without reverse projection")
	d.path.settle()
	equal(observed.y, stop(1000).y, "fallback coordinates are those submitted")
	check(type(observed.title) == "string" and observed.title ~= "", "fallback stop has a title")
	unsubscribeFallback()
	API.Cancel("o")
	env.C_Map.GetMapPosFromWorldPos = projection
end
print("api_observe_spec: " .. checks .. " checks passed")
