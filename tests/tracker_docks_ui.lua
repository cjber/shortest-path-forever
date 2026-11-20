-- The departures section, at every dock for both factions with and without the other faction's routes: each block it
-- shows has a departure under it, and the section's header names the kind those departures are. A dock whose every
-- route is hidden shows no block, so with no journey the section, header and all, goes away.
local dir = arg[0]:match("^(.*)/") or "tests"
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [==[
local tracker = ShortestPathForeverObjectiveTracker
local HEADER = { boat = "Boats", zeppelin = "Boats", lift = "Lifts", tram = "Deeprun Tram" }
local faction
_G.UnitFactionGroup = function()
	return faction
end
ns.db.tracker, ns.db.journeyTracker = true, true
assert(not ns.HasJourney(), "no journey is set")
local checked, empty = 0, 0
for _, side in ipairs({ "Alliance", "Horde" }) do
	for _, other in ipairs({ false, true }) do
		faction, ns.db.otherFaction = side, other
		for dockID, dock in pairs(ns.Docks) do
			posX, posY, posMap = dock.x, dock.y, dock.map
			ns.RefreshTracker()
			local where = string.format("dock %d (%s, other faction %s)", dockID, side, tostring(other))
			local departures = ns.Timetable.ByDestination(dockID)
			if #departures == 0 then
				empty = empty + 1
				assert(#tracker.blocks == 0, where .. " has no departures, so it shows no block")
				assert(tracker:GetContentsHeight() == 0, where .. " leaves no section in the column")
			else
				assert(#tracker.blocks == 1, where .. " shows its departures")
			end
			for _, block in ipairs(tracker.blocks) do
				assert(#block.rows > 0, where .. ": block " .. tostring(block.key) .. " has no rows")
			end
			if #tracker.blocks > 0 then
				local kind = departures[1].kind
				local header = tracker.Header.Text:GetText()
				assert(header == HEADER[kind], where .. " is headed " .. tostring(header))
			end
			checked = checked + 1
		end
	end
end
assert(empty > 0, "some docks serve only one faction")
assert(#errors == 0, table.concat(errors, "\n"))
print(
	string.format("tracker_docks_ui: %d dock states, %d with nothing shown, no empty section ok", checked, empty)
)
]==]))()
