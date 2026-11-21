-- Town services on the minimap (UI/MinimapPins.lua with UI/TownServices.lua): a kind ticked in the world map's
-- filter shows on the minimap with its service art and tooltip, an unticked one hides, a filter change refreshes,
-- the minimap switch hides every pin, and only places on the player's map and in view are drawn.
local dir = arg[0]:match("^(.*)/") or "tests"
do
	local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
	assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture for tests/minimap_services_spec.lua")
end
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [==[
local layer = ShortestPathForeverMinimapPins
local function group(section, key, label, tracking)
 return { section = section, key = key, label = label, icon = tracking, tracking = tracking, npcs = {} }
end
local groups = {
 group("services", "bank", "Bank", "Banker"),
 group("services", "innkeeper", "Innkeeper", "Innkeeper"),
}
local function place(id, name, x, y, map)
 return { id = id, name = name, map = 14, x = 0.5, y = 0.5, world = { map = map or 1, x = x, y = y } }
end
-- Orgrimmar's own box (Data/Zones.lua) holds the first two; the third is a continent away on another map.
local index = {
 bank = { place(1, "Banker One", 1800, -4900), place(3, "Far Banker", 1800, -4900, 2) },
 innkeeper = { place(2, "Innkeeper Two", 1830, -4900) },
}
local state = "building"
ns.NearbyServices = {
 Request = function() end,
 State = function() return state end,
 Index = function() return index end,
 Groups = function() return groups end,
 Items = function() return nil end,
 OnReady = function() end,
 Navigate = function() return true end,
}
local function shown()
 local list = {}
 for _, pin in ipairs(layer.children or {}) do
  if pin:IsShown() then list[#list + 1] = pin end
 end
 return list
end
local function services()
 local list = {}
 for _, pin in ipairs(shown()) do
  if pin.entry.service then list[#list + 1] = pin end
 end
 return list
end
local function names()
 local list = {}
 for _, pin in ipairs(services()) do list[#list + 1] = pin.entry.service.name end
 table.sort(list)
 return table.concat(list, ",")
end

posX, posY, posZ, posMap = 1800, -4900, 0, 1
ns.db.minimapPins = true
ns.db.journey = true
ns.db.townServices = "all"
ns.RefreshMinimapPins()
assert(#services() == 0, "nothing shows while the catalogue is still building")
state = "ready"
ns.RefreshMinimapPins()
assert(names() == "Banker One,Innkeeper Two", "the ready catalogue shows the player's map only: " .. names())
local bank
for _, pin in ipairs(services()) do
 if pin.entry.service.name == "Banker One" then bank = pin end
end
assert(bank.Texture.atlas == "Banker", "the service wears the client's map icon, as on the world map")
bank.scripts.OnEnter(bank)
assert(GameTooltip:IsOwned(bank), "hovering shows a tooltip")
assert(tip[1] == "# Bank" and tip[2] == "  Banker One", "the world map's tooltip names the service")
bank.scripts.OnLeave(bank)

-- An unticked kind hides; a filter change refreshes at once.
ns.SetTownServiceGroupShown(groups[1], false)
assert(names() == "Innkeeper Two", "an unticked kind leaves the minimap: " .. names())
ns.SetTownServiceGroupShown(groups[1], true)
assert(names() == "Banker One,Innkeeper Two", "ticking it again brings it back: " .. names())

-- The town level setting applies as on the world map.
ns.db.townServices = "off"
ns.RefreshTownServices()
assert(#services() == 0, "town services off shows none on the minimap")
ns.db.townServices = "all"
ns.RefreshTownServices()

-- The rim: out of view hides.
posX = 1800 + 250
ns.RefreshMinimapPins()
assert(#services() == 0, "services beyond the minimap's reach are not drawn")
posX = 1800

-- The minimap switch.
ns.db.minimapPins = false
ns.RefreshMinimapPins()
assert(not layer:IsShown(), "the minimap switch off hides the layer")
ns.db.minimapPins = true
ns.RefreshMinimapPins()
assert(names() == "Banker One,Innkeeper Two", "and on shows them again")

-- Scale follows minimapPinScale.
ns.db.minimapPinScale = 50
ns.RefreshMinimapPins()
assert(bank:GetWidth() == 8, "minimap icon size scales service pins")
ns.db.minimapPinScale = 100
ns.RefreshMinimapPins()
-- Budget: a big catalogue (a continent's worth of NPCs) stays cheap to redraw, as only the player's map is read.
local many = {}
for i = 1, 4000 do
 local x, y = 1800 + (i % 80) * 40 - 1600, -4900 + math.floor(i / 80) * 40 - 1000
 many[i] = place(100 + i, "Banker " .. i, x, y, i % 4 == 0 and 1 or 2)
end
index = { bank = many, innkeeper = {} }
ns.RefreshMinimapPins()
local start = os.clock()
for i = 1, 600 do
 posX = 1800 + i * 0.5
 ns.RefreshMinimapPins()
end
local per = (os.clock() - start) * 1000 / 600
print(string.format("minimap_services_spec: %.3f ms per rebuild and redraw with 4000 services", per))
assert(per < 3, "a service-heavy minimap redraw stays inside the 3 ms frame budget")
ns.HideMinimapPins()
assert(#errors == 0, table.concat(errors, "\n"))
print("minimap_services_spec: ok")
]==]))()
