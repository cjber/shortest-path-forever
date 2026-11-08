-- Run from the repository root: luajit tests/pin_states_spec.lua
-- The addon's hoverable icons that are not world map pins: the minimap's transport pins. Each wears the stock highlight
-- on hover and the stock pushed look while the button is held, and returns to its rest look on release or when the
-- pointer leaves.
local dir = arg[0]:match("^(.*)/") or "tests"

local probe = "tools/.cache/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/Spinner.lua"
do
	local handle = io.open(probe)
	if handle then
		handle:close()
	else
		local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
		assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture for tests/pin_states_spec.lua")
	end
end

local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [==[
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end

--[[ The minimap's transport pins: the same icon again with ADD on hover, pushed while held ]]
local layer = ShortestPathForeverMinimapPins
local dock = ns.Docks[7].walk or ns.Docks[7]
posX, posY, posZ, posMap = dock.x + 60, dock.y, dock.z or 0, dock.map
ns.RefreshMinimapPins()
local ferry
for _, pin in ipairs(layer.children or {}) do
	if pin:IsShown() and pin.entry and pin.entry.cluster and pin.entry.cluster.docks[1].id == 7 then
		ferry = pin
	end
end
check(ferry ~= nil, "the minimap shows the pier's ferry")
check(ferry.HighlightTexture ~= nil and ferry.HighlightTexture.hidden, "a minimap pin rests unlit")
local width, height, anchor = ferry:GetWidth(), ferry:GetHeight(), ferry.anchor
ferry.scripts.OnEnter(ferry)
check(not ferry.HighlightTexture.hidden, "hovering a minimap pin lights its own art")
check(
	ferry.HighlightTexture.atlas == ferry.Texture.atlas and ferry.HighlightTexture.texture == ferry.Texture.texture,
	"a minimap pin wears the same art on hover"
)
check(ferry.Texture.offsetX == nil and ferry.Texture.offsetY == nil, "hover leaves it where it is")
ferry.scripts.OnMouseDown(ferry)
check(ferry.Texture.offsetX == 1 and ferry.Texture.offsetY == -1, "pressing pushes the minimap icon down and right")
check(
	ferry:GetWidth() == width and ferry:GetHeight() == height and ferry.anchor == anchor,
	"a pressed minimap pin keeps its size, anchor and hit rect"
)
ferry.scripts.OnMouseUp(ferry)
check(ferry.Texture.offsetX == 0 and ferry.Texture.offsetY == 0, "releasing restores the minimap icon")
ferry.scripts.OnMouseDown(ferry)
ferry.scripts.OnLeave(ferry)
check(ferry.Texture.offsetX == 0 and ferry.Texture.offsetY == 0, "leaving releases a held minimap pin")
check(ferry.HighlightTexture.hidden, "leaving leaves the rest look")
ferry.scripts.OnMouseUp(ferry)
check(#errors == 0, table.concat(errors, "\n"))

print(("pin_states_spec: %d checks: minimap hover, pressed and rest states ok"):format(checks))
]==]))()
