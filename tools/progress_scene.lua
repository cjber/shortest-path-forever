local harness = dofile("tests/progress_harness.lua")
local h = harness()
for _ = 1, 3 do
	h.ns.ProgressJourneyChanged(nil, "arrived")
end
for id = 1, 7 do
	h:Fire(
		"CHAT_MSG_ADDON",
		"WFAStats",
		"1|spf|routes_completed|all|" .. (10 + id) .. "|1000",
		"GUILD",
		"Example" .. id .. "-Other"
	)
end
h.printed = {}
h.ns.PrintTravelLeaderboard("routesCompleted")
for _, line in ipairs(h.printed) do
	io.write(line, "\n")
end
