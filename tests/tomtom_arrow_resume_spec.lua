-- TomTom's arrow recovers the active Shortest Path target across login and waypoint changes (#1360).
local BootArrow = assert(loadfile("tests/tomtom_arrow_driver.lua"))()
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- #1360: a guide already has its step before the player's position becomes available at login.
do
	local c = BootArrow({ tomtomArrow = true }, true)
	c.driver.path.settle()
	equal(c.API.CurrentStop("RestedXP"), 1, "login retries the restored guide without a manual waypoint change")
	equal(c.ns.TomTomArrowActive(), true, "TomTom leads the restored guide after login")
	equal(c.crazy.hidden, false, "the restored guide's TomTom arrow is visible")
end

-- The bridge deduplicates against the same TomTom waypoint and later removes that shared table on step advance.
do
	local c = BootArrow({ tomtomArrow = true })
	local start = { map = 1, x = 0, y = 0 }
	local firstStop = { map = 1, x = 0, y = -2500, label = "RXP Step 1" }
	local stop = { map = 1, x = 0, y = -5000, label = "RXP Step 2" }
	c.driver.move(start)
	c.ns.PointGuideArrow({ start, firstStop }, nil, firstStop)
	c.ns.PointGuideArrow({ start, stop }, nil, stop)
	local nextStep = c.tomtom.Arrow()
	local bridge = c.tomtom:AddWaypoint(nextStep[1], nextStep[2], nextStep[3], {
		title = nextStep.title,
		persistent = false,
		crazy = false,
	})
	equal(bridge, nextStep, "the bridge shares the selected waypoint through TomTom deduplication")
	c.tomtom:RemoveWaypoint(bridge)
	c.tomtom:ArrowUpdate()
	c.runTimers()
	equal(c.ns.TomTomArrowActive(), true, "TomTom resumes the current step after bridge removal")
	equal(c.tomtom.Arrow().title, "RXP Step 2", "the recovered arrow points at the current step")
	equal(c.tomtom:IsValidWaypoint(c.tomtom.Arrow()), true, "the recovered waypoint is registered")
end

-- TomTom autoqueues a manual waypoint even with TomTom following turned off.
do
	local c = BootArrow({ tomtomArrow = true })
	c.driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 0, y = -5000 })
	local ours = c.tomtom.Arrow()
	local manual = c.tomtom:Way(1, 10, 20, "Manual waypoint")
	equal(c.ns.TomTomArrowActive(), false, "ownership reflects the externally selected waypoint")
	c.runTimers()
	equal(c.tomtom.Arrow(), ours, "a manual waypoint does not displace the active Shortest Path target")
	equal(c.tomtom:IsValidWaypoint(manual), true, "the manual waypoint stays registered")
	c.ns.ClearJourney()
	c.tomtom:SetCrazyArrow(manual, 15, manual.title)
	c.runTimers()
	equal(c.tomtom.Arrow(), manual, "TomTom keeps the manual selection after the journey ends")
end

print("tomtom arrow resume: ok, " .. checks .. " checks")
