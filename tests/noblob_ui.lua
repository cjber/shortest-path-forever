-- A client without the blob widget: the held stop keeps its button and line inside its quest's area, and nothing
-- is acquired from the missing template.
local dir = arg[0]:match("^(.*)/") or "tests"
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [[
visible, WorldMapFrame.shown = true, true
posX, posY, posMap, facing = 0, 0, 1, 0
mapID, zoom = 14, 1
blobWidget = false
insideQuestBlob[7] = true
local api = ShortestPathForever.API
assert(api.NavigateRoute("Test", {
 { map = 14, x = 0.5, y = 0.5, title = "Area", kind = "objective", hold = true, questID = 7 },
}))
settle()
for _ = 1, 2 do
 for _, provider in ipairs(providers) do provider:RefreshAllData() end
 assert(#(active.ShortestPathForeverAreaPinTemplate or {}) == 0, "no area pin without the widget")
 assert(#active.ShortestPathForeverGoalPinTemplate == 1, "the stop keeps its button")
end
assert(#errors == 0, table.concat(errors, "\n"))
print("noblob_ui: a client without the blob widget keeps the stop ok")
]]))()
