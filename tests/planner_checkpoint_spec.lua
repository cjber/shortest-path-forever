local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)

-- Planner is loaded before Routing/Path.lua in the TOC.  The hook must therefore
-- be resolved when Plan starts, rather than captured at module load.
local calls = 0
ns.Path = {
	Checkpoint = function()
		calls = calls + 1
	end,
}
local plan = ns.Planner.Plan({
	from = { map = 1, x = 0, y = 0 },
	to = { map = 1, x = 70, y = 0 },
	now = 0,
	walkSpeed = 7,
})
assert(plan and calls > 0, "late-loaded Path checkpoint was not called")
print("planner_checkpoint_spec: ok")
