-- Run from the repository root: luajit tests/docktooltip_spec.lua
-- The dock tooltip must tolerate a cluster whose docks have no departures left. A pin's cluster can outlive the
-- filter that built it for a frame (a refresh queued in combat), and UI/Map.lua's shared title then indexed the first
-- departure of an empty group and raised. The smoke sweep names this crash; this pins the fix.
local dir = arg[0]:match("^(.*)/") or "tests"

-- The fixture runs against checksum-pinned Blizzard source; a lone spec run fetches it like tests/smoke_spec.lua.
local probe = "tools/.cache/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/Spinner.lua"
do
	local handle = io.open(probe)
	if handle then
		handle:close()
	else
		local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
		assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture for tests/docktooltip_spec.lua")
	end
end

local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [==[
-- Two docks no route calls at: both have no departures, so the cluster's two groups are empty.
local cluster = {
	docks = { { id = 999998, x = 0, y = 0 }, { id = 999999, x = 0, y = 0 } },
	kinds = { boat = true, lift = true },
}
assert(#ns.Timetable.Departures(999998) == 0, "the dock has no departures to draw")
ns.AddDockTooltip(cluster)
assert(#errors == 0, table.concat(errors, "\n"))
print("dock tooltip: clusters with no departures are safe")
]==]))()
