---@class SPFNamespace
local ns = select(2, ...)

-- Shortest Path's own lines in /path report (UI/Report.lua; the pattern is cjber/adventure-guide-forever
-- docs/report-window.md): the travel settings, the journey with its goal and every step of its plan, the search,
-- the ride, the bind point, and with /path debug on, the last samples of the ride trace. Read from the journey as it
-- stands: nothing is planned or searched for the report. Field labels are English; place names are the client's.

local TRACE_SHOWN = 5
local SETTINGS = "Settings: journeys %s, teleports %s (hearth saving %ss), other faction %s, TomTom %s/follow %s, "
	.. "RestedXP %s"
local MODES = { [true] = "on", [false] = "off" }

---@param value any
---@return string
local function OnOff(value)
	return MODES[value == true]
end

-- A world point as the map shows it: "map 1429 42.1, 65.3", or its world yards when no zone holds it.
---@param point SPFPoint
---@return string
local function Place(point)
	local location = ns.Locate(point)
	if location then
		return ("map %d %s, %s"):format(location.uiMap, ns.Report.Percent(location.x), ns.Report.Percent(location.y))
	end
	return ("continent %s %.0f, %.0f"):format(tostring(point.map), point.x, point.y)
end

-- The report's Shortest Path lines.
---@return string[]
function ns.ReportLines()
	local db = ns.db
	local lines = {
		SETTINGS:format(
			OnOff(db.journey),
			OnOff(db.teleports),
			tostring(db.hearthMinimumSavings or 0),
			OnOff(db.otherFaction),
			OnOff(db.tomtom),
			OnOff(db.tomtomFollow),
			OnOff(db.restedxp)
		),
	}
	local bind = ns.charDB.bind
	lines[#lines + 1] = ("Bind point: %s"):format(bind and (bind.name .. ", " .. Place(bind)) or "not known")
	local goal = ns.JourneyGoal()
	if not goal then
		lines[#lines + 1] = ns.HasJourney() and "Journey: corpse run" or "Journey: none"
	else
		local owner = ns.JourneyOwner()
		local stops, stop = ns.JourneyStops()
		lines[#lines + 1] = ("Journey: %s, owner %s%s, guided %s"):format(
			ns.PlaceLabel(goal),
			owner or "player",
			stops and (", stop %d of %d"):format(stop, #stops) or "",
			OnOff(ns.IsJourneyGuided())
		)
		lines[#lines + 1] = "Goal: " .. Place(goal)
		local pending, rounds = ns.JourneyStatus()
		local _, _, plan, index = ns.JourneyInfo()
		lines[#lines + 1] = ("Search: %s, %d settle rounds"):format(pending and "under way" or "settled", rounds or 0)
		if plan then
			local previous = plan.legs[1] and plan.legs[1].depart or 0
			for position, leg in ipairs(plan.legs) do
				lines[#lines + 1] = ("%s%d. %s to %s, %ds%s"):format(
					position == index and "> " or "  ",
					position,
					leg.mode,
					ns.LegLabel(leg),
					math.floor((leg.arrive - previous) / 1000 + 0.5),
					leg.wait and leg.wait > 0 and (" (waits %ds)"):format(math.floor(leg.wait / 1000 + 0.5)) or ""
				)
				previous = leg.arrive
			end
		else
			lines[#lines + 1] = "Plan: none yet"
		end
	end
	local ride = ns.CurrentRide()
	lines[#lines + 1] = ("Ride: %s%s"):format(
		ride and ("route " .. ride) or (ns.IsObservingRide() and "being matched" or "none"),
		UnitOnTaxi("player") and ", on a flight" or ""
	)
	-- The raw samples are kept only while /path debug is on: server time, continent, x, y, z, speed, fits.
	local trace = db.debug and db.trace
	if trace and trace[1] then
		lines[#lines + 1] = ("Ride trace (last %d of %d):"):format(math.min(TRACE_SHOWN, #trace), #trace)
		for position = math.max(1, #trace - TRACE_SHOWN + 1), #trace do
			local sample = trace[position]
			lines[#lines + 1] = ("  %s %s %.1f, %.1f, %.1f at %s %s"):format(
				tostring(sample[1]),
				tostring(sample[2]),
				tonumber(sample[3]) or 0,
				tonumber(sample[4]) or 0,
				tonumber(sample[5]) or 0,
				tostring(sample[6]),
				tostring(sample[7] or "")
			)
		end
	else
		lines[#lines + 1] = "Ride trace: off (/path debug keeps one)"
	end
	return lines
end
