-- Exercise the direct tab entrance through the pinned ForeverCore Select/Sync/NotifyShown implementation.
local file = assert(io.open("tests/services_panel_spec.lua"))
local source = file:read("*a")
file:close()
local replacements
source, replacements = source:gsub(
	"env.ForeverCore = { QuestLogTabs = QuestLogTabs }",
	[[
map.ContentFrames = {}
map.MapLegendTab = frame("Button", "Legend", map)
map.MapLegendTab.sized = true
map.QuestsTab = map.MapLegendTab
env.WorldMapFrame = frame("Frame", "WorldMap")
env.WorldMapFrame.sized = true
env.QuestMapFrameOverrides = { questTabHidden = false }
env.EventRegistry = { RegisterCallback = function() end }
env.hooksecurefunc = function() end
local create = env.CreateFrame
env.CreateFrame = function(...)
 local tab = create(...)
 tab.Icon = region()
 tab.SetCustomOnMouseUpHandler = function(self, callback) self.click = callback end
 return tab
end
local core = dofile("tests/forever_core.lua").load(env, "ForeverCore", { "UI/QuestLogTabs.lua" })
local api = core.QuestLogTabs
local register, setShown = api.Register, api.SetTabShown
api.Register = function(key, spec)
 ns.registered = { key = key, spec = spec }
 spec.safeCall = function(_, callback, ...) callback(...) end
 ns.tab = register(key, spec)
 return ns.tab
end
api.SetTabShown = function(key, shown)
 ns.tabHidden = shown == false
 ns.tabShownCalls[#ns.tabShownCalls + 1] = { key = key, shown = shown }
 return setShown(key, shown)
end
env.ForeverCore = { QuestLogTabs = api }
]],
	1
)
assert(replacements == 1, "the panel fixture exposes its core boundary")
source = source:gsub("ns.registered.spec.shown%(false%)", "env.ForeverCore.QuestLogTabs.ShowQuests()")
assert(loadstring(source, "@services_panel_direct_tab_fixture"))()
print("services_panel_direct_tab: real ForeverCore tab entrance: ok")
