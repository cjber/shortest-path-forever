-- Run from the repository root: luajit tests/map_art_spec.lua
-- The world map's pins keep the client's own art (UI/Map.xml, UI/Map.lua): the glow layers the client art audit removed
-- are gone from the templates and from the pins' code, and a super-tracked flight point still wears the stock marker.
local checks = 0
local function check(value, label)
	checks = checks + 1
	assert(value, label)
end

local file = assert(io.open("UI/Map.xml"))
local xml = file:read("*a")
file:close()

for _, gone in ipairs({
	"UI-QuestPoi-OuterGlow",
	"UI-QuestPoi-InnerGlow",
	'parentKey="Glow"',
	'parentKey="SuperTrackGlow"',
}) do
	check(not xml:find(gone, 1, true), "UI/Map.xml draws no removed glow: " .. gone)
end
check(xml:find('parentKey="SuperTrackMarker"', 1, true), "a super-tracked flight point keeps the stock marker")

-- No runtime file under UI/ may bring a removed glow or the Legion portal file back.
for _, gone in ipairs({ "UI-QuestPoi-OuterGlow", "UI-QuestPoi-InnerGlow", "map-icon-suramardoor" }) do
	local pipe = assert(io.popen("git grep -l -F '" .. gone .. "' -- UI"))
	local hits = pipe:read("*a")
	pipe:close()
	check(hits == "", gone .. " is referenced again: " .. hits)
end

print(string.format("map_art_spec: %d checks passed", checks))
