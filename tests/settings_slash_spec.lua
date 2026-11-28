local h = dofile("tests/settings_spec.lua")
local env, ns, ways = h.env, h.ns, h.ways

-- /path report shows the report, its lines run through SafeCall; lines that fail still show the rest.
local shownReport
ns.core.SafeCall = function(_, fn, ...)
	return pcall(fn, ...)
end
ns.core.Report = {
	Text = function(lines)
		return table.concat(lines, "\n")
	end,
	Show = function(text)
		shownReport = text
	end,
}
ns.ReportLines = function()
	return { "Journey: none" }
end
ns.core.Report.Command = function(command)
	if command == "report" then
		local ok, lines = ns.core.SafeCall("report lines", ns.ReportLines)
		ns.core.Report.Show(ns.core.Report.Text(ok and lines or { "Report lines failed: " .. tostring(lines) }))
		return true
	end
	return false
end
env.SlashCmdList.SHORTESTPATHFOREVER("report")
assert(shownReport == "Journey: none", "/path report shows the report")
ns.ReportLines = function()
	error("broke", 0)
end
env.SlashCmdList.SHORTESTPATHFOREVER("report")
assert(shownReport == "Report lines failed: broke", "failing lines are said in their place")

-- /path way takes TomTom's /way line, whether or not /way itself is free.
env.SlashCmdList.SHORTESTPATHFOREVER("way Elwynn Forest 42.1 65.3 Goldshire")
assert(ways[1] == "Elwynn Forest 42.1 65.3 Goldshire", "/path way hands on the rest of the line")
env.SlashCmdList.SHORTESTPATHFOREVER("way")
assert(ways[2] == "", "a bare /path way still answers, with its usage")

print("settings slash commands: ok")
