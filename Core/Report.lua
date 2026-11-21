---@type string
local addonName = ...
---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Shortest Path's own lines in /path report (ForeverCore's report window; the pattern is
-- cjber/adventure-guide-forever docs/report-window.md): the travel settings, the bind point, the ride and, with
-- /path debug on, the last samples of its trace, then the corpse run and the journey with its goal and every step
-- of its plan. Compact steps precede walk evidence, with the active walk first, so
-- earlier walks do not crowd the active step out of the report's cap. Read from the journey as it stands,
-- paused or behind a corpse run:
-- nothing is planned or searched for the report. Field labels are English; place names are the client's.

local TRACE_SHOWN = 5
local SETTINGS = "Settings: journeys %s, hearth %s (saving %ss), class teleports %s (saving %ss), "
	.. "other faction %s, TomTom %s/follow %s, RestedXP %s, Guidelime %s"

---@param value any
---@return string
local function OnOff(value)
	return value == true and "on" or "off"
end

---@param ms number
---@return integer
local function Seconds(ms)
	return math.floor(ms / 1000 + 0.5)
end

---@param uiMap integer
---@param x number
---@param y number
---@return string
local function MapPlace(uiMap, x, y)
	local percent = ns.core.Report.Percent
	return ("map %d %s, %s"):format(uiMap, percent(x), percent(y))
end

-- A world point as the map shows it: "map 1429 42.1, 65.3", or its world yards when no zone holds it.
---@param point SPFPoint
---@return string
local function Place(point)
	local location = ns.Locate(point)
	if location then
		return MapPlace(location.uiMap, location.x, location.y)
	end
	return ("continent %s %.0f, %.0f"):format(tostring(point.map), point.x, point.y)
end

-- Keep nil distinct from a real zero, and retain the exact world coordinates given to the walk search.
---@param value any
---@return string
local function Value(value)
	if value == nil then
		return "unknown"
	end
	return type(value) == "number" and ("%.17g"):format(value) or tostring(value)
end

---@param point SPFPoint
---@return string
local function Endpoint(point)
	return ("map %s x %s y %s z %s"):format(Value(point.map), Value(point.x), Value(point.y), Value(point.z))
end

-- Compact evidence for a bug report, with the clicked map coordinates and the exact world point.
---@param marks SPFMapReportMark[]
---@return string
function ns.MapReportText(marks)
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "-"
	local gameVersion, build = GetBuildInfo()
	local L = ns.L
	local lines = {
		("%s %s | WoW %s (%s) | %s"):format(addonName, version, gameVersion, build, L["Road and wall report"]),
	}
	local goal = ns.JourneyGoal()
	if goal then
		local plan = ns.JourneyPlan()
		local first = plan and plan.legs[1]
		local start = first and first.from or ns.JourneySearch.Origin(goal)
		lines[#lines + 1] = L["Journey start: %s"]:format(start and Endpoint(start) or Value(nil))
		lines[#lines + 1] = L["Journey goal: %s"]:format(Endpoint(goal))
	end
	for _, mark in ipairs(marks) do
		local location = ns.Locate(mark.world)
		local mapInfo = not location and C_Map.GetMapInfo(mark.map) or nil
		lines[#lines + 1] = ("%s | %s | %s | %s"):format(
			mark.kind,
			MapPlace(mark.map, mark.x, mark.y),
			Endpoint(mark.world),
			location and location.zone or mapInfo and mapInfo.name or "unknown"
		)
	end
	return table.concat(lines, "\n")
end

---@param lines string[]
---@param leg SPFLeg
---@param position integer
local function WalkEvidence(lines, leg, position)
	lines[#lines + 1] = ("    Walk %d: "):format(position) .. Endpoint(leg.from) .. " -> " .. Endpoint(leg.to)
	lines[#lines + 1] = ("    Geometry: measured %s, drawn %s, placeholder %s, deferred %s; estimated cost %s"):format(
		Value(leg.measured),
		Value(leg.walkDrawn),
		Value(leg.walkPlaceholder),
		Value(leg.walkDeferred),
		Value(leg.estimated)
	)
	local data = ShortestPathForeverPathData and ShortestPathForeverPathData[leg.from.map]
	if data then
		lines[#lines + 1] = (
			"    Nav map %s: format %s, cells %s, zstep %s, steep %s, climbChecked %s" .. "; revision unknown"
		):format(
			Value(leg.from.map),
			Value(data.format),
			Value(data.cells),
			Value(data.zstep),
			Value(data.steep),
			Value(data.climbChecked)
		)
	else
		lines[#lines + 1] = "    Nav map " .. Value(leg.from.map) .. ": unknown"
	end
end

-- Each step as the tracker times it (its own span, the wait apart), the one under way marked, and why a walk failed.
---@param lines string[]
---@param legs SPFLeg[]
---@param index integer
local function Steps(lines, legs, index)
	for position, leg in ipairs(legs) do
		lines[#lines + 1] = ("%s%d. %s to %s, %ds%s%s"):format(
			position == index and "> " or "  ",
			position,
			leg.mode,
			ns.LegLabel(leg),
			Seconds(leg.arrive - leg.depart),
			leg.wait and leg.wait > 0 and (", waits %ds"):format(Seconds(leg.wait)) or "",
			leg.walkError and (", walk failed: %s"):format(leg.walkError) or ""
		)
	end
	local active = legs[index]
	if active and active.mode == "walk" then
		WalkEvidence(lines, active, index)
	end
	for position, leg in ipairs(legs) do
		if position ~= index and leg.mode == "walk" then
			WalkEvidence(lines, leg, position)
		end
	end
end

---@param lines string[]
local function Trace(lines)
	-- The raw samples are kept only while /path debug is on: server time, continent, x, y, z, speed, fits.
	local trace = ns.db.debug and ns.db.trace
	if not (trace and trace[1]) then
		lines[#lines + 1] = "Ride trace: off (/path debug keeps one)"
		return
	end
	-- The last samples taken aboard, which carry the ride's fits: a report taken after getting off still has them.
	local last = #trace
	for position = #trace, 1, -1 do
		if trace[position][7] and trace[position][7] ~= "" then
			last = position
			break
		end
	end
	local first = math.max(1, last - TRACE_SHOWN + 1)
	lines[#lines + 1] = ("Ride trace (%d to %d of %d):"):format(first, last, #trace)
	for position = first, last do
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
end

-- The report's Shortest Path lines.
---@return string[]
function ns.ReportLines()
	local db = ns.db
	local lines = {
		SETTINGS:format(
			OnOff(db.journey),
			OnOff(db.useHearthstone),
			tostring(db.hearthMinimumSavings or 0),
			OnOff(db.teleports),
			tostring(db.teleportMinimumSavings or 0),
			OnOff(db.otherFaction),
			OnOff(db.tomtom),
			OnOff(db.tomtomFollow),
			OnOff(db.restedxp),
			OnOff(db.guidelime)
		),
	}
	lines[#lines + 1] = (
		"Current walk settings: avoidHighZones %s, followRoads %s, roadDetour %s, " .. "useWaterWalking %s"
	):format(Value(db.avoidHighZones), Value(db.followRoads), Value(db.roadDetour), Value(db.useWaterWalking))
	local avoided = ns.charDB.avoided or {}
	lines[#lines + 1] = ("Avoided transport: %d"):format(#avoided)
	for _, entry in ipairs(avoided) do
		lines[#lines + 1] = ("  %s %s (%s)"):format(entry.kind, table.concat(entry.ids, ", "), entry.name)
	end
	local bind = ns.charDB.bind
	lines[#lines + 1] = ("Bind point: %s"):format(bind and (bind.name .. ", " .. Place(bind)) or "not known")
	local known = {}
	for _, continent in ipairs(ns.KnownFlightPointsByContinent()) do
		known[#known + 1] = ("%s %d"):format(continent.name, continent.known)
	end
	lines[#lines + 1] = "Flight points known: " .. table.concat(known, ", ")
	local ride = ns.CurrentRide()
	lines[#lines + 1] = ("Ride: %s%s"):format(
		ride and ("route " .. ride) or (ns.IsObservingRide() and "being matched" or "none"),
		UnitOnTaxi("player") and ", on a flight" or ""
	)
	Trace(lines)
	local goal = ns.JourneyGoal()
	-- A corpse run guides you back first; a journey planned before it waits behind it.
	local corpse = ns.Corpse and select(3, ns.Corpse.Info())
	if corpse then
		lines[#lines + 1] = "Corpse run:" .. (goal and " the journey waits behind it" or "")
		Steps(lines, corpse.legs, 1)
	end
	if not goal then
		lines[#lines + 1] = "Journey: none"
		return lines
	end
	local owner = ns.JourneyOwner()
	local stops, stop = ns.JourneyStops()
	lines[#lines + 1] = ("Journey: %s, owner %s%s, guided %s"):format(
		ns.PlaceLabel(goal),
		owner or "player",
		stops and (", stop %d of %d"):format(stop, #stops) or "",
		OnOff(ns.IsJourneyGuided())
	)
	lines[#lines + 1] = "Goal: " .. Place(goal)
	local pending, rounds, costError, _, timing = ns.JourneyStatus()
	lines[#lines + 1] = ("Search: %s, %d settle rounds%s"):format(
		pending and "under way" or "settled",
		rounds or 0,
		costError and (", walk failed: %s"):format(costError) or ""
	)
	for _, mark in ipairs({ "first", "last" }) do
		local at = timing and timing[mark]
		if at then
			lines[#lines + 1] = ("Search %s route: %.2f s, %d work frames, %.0f ms path work, %.0f fps"):format(
				mark,
				at.ms / 1000,
				at.frames,
				at.cpu,
				at.fps or 0
			)
		end
	end
	local plan, index = ns.JourneyPlan()
	if plan then
		lines[#lines + 1] = "Plan water walking: " .. Value(plan.waterMode)
		Steps(lines, plan.legs, index)
	else
		lines[#lines + 1] = "Plan: none yet"
	end
	return lines
end
