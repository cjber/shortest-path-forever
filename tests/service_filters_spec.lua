-- Per-kind visibility reaches the real map layer, including a mixed-service NPC's icon cache.
local source = ""
for _, part in ipairs({ "tests/ui_client.lua", "tests/ui_map.lua" }) do
	local file = assert(io.open(part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [==[
local groups = {
 { section = "trainers", key = "profession:164", label = "Blacksmithing", tracking = "Profession" },
 { section = "trainers", key = "profession:165", label = "Leatherworking", tracking = "Class" },
 { section = "trainers", key = "class", label = "Class trainer", tracking = "Food" },
 { section = "trainers", key = "portal", label = "Portal trainer", tracking = "MagePortalAlliance" },
}
local place = { id = 1, name = "Trainer", map = 14, x = .5, y = .5, world = { map = 1, x = 0, y = 0 } }
local index = { ["profession:164"] = { place }, ["profession:165"] = { place }, class = { place }, portal = { place } }
ns.NearbyServices = { State = function() return "ready" end, Index = function() return index end,
 Groups = function() return groups end }
local mapInfo = C_Map.GetMapInfo
C_Map.GetMapInfo = function(id) local info = mapInfo(id); info.mapType = Enum.UIMapType.Zone; return info end
ns.db.townServices = "all"
ns.db.townServiceKinds = { ["profession:164"] = false }
mapID, zoom = 1414, 1
setMapShown(true)
ns.RefreshTownServices()
local function pin()
 return ns.Canvas.Pools(WorldMapFrame).ShortestPathForeverServicePinTemplate.active[1]
end
local function tooltip()
 local lines = {}
 GameTooltip_SetTitle = function(_, text) lines[#lines + 1] = text end
 GameTooltip_AddNormalLine = function(_, text) lines[#lines + 1] = text end
 pin():OnMouseEnter()
 return table.concat(lines, "\n")
end
assert(not tooltip():find("Blacksmithing", 1, true), "hiding Blacksmithing must not leave it on a mixed NPC pin")
assert(tooltip():find("Leatherworking", 1, true), "other professions remain shown")
assert(pin().Texture.atlas == "Class", "the icon uses the first shown profession")
ns.SetTownServiceGroupShown(groups[2], false)
assert(not tooltip():find("Leatherworking", 1, true), "another per-kind change repaints an unchanged NPC pin")
assert(ns.TownServiceGroupShown(groups[3]), "class remains independent")
assert(pin().Texture.atlas == "Food", "the unchanged NPC pin repaints after its primary service is hidden")
ns.SetTownServiceGroupShown(groups[4], false)
assert(ns.TownServiceGroupShown(groups[3]), "hiding portals does not hide class trainers")
local boxes, scrollExtent = {}, nil
local root = { CreateDivider = function() end }
function root:CreateButton() return self end
function root:CreateRadio() end
function root:SetScrollMode(extent) scrollExtent = extent end
function root:CreateCheckbox(label, get, click)
 boxes[#boxes + 1] = { label = label, get = get, click = click }
end
menus.MENU_WORLD_MAP_TRACKING(nil, root)
assert(scrollExtent == 400 and #boxes == 4, "the per-kind trainer menu scrolls")
for at, group in ipairs(groups) do
 assert(boxes[at].label == group.label, "profession, class and portal labels follow the catalogue")
end
assert(boxes[3].get() and not boxes[4].get(), "menu reads the same class and portal choices")
boxes[2].click()
assert(ns.TownServiceGroupShown(groups[2]) and not ns.TownServiceGroupShown(groups[1]),
 "menu click changes one profession without changing another")
ns.db.townServiceKinds = nil
ns.db.townServiceProfessions = false
assert(not ns.TownServiceGroupShown(groups[1]), "old profession preference remains the fallback")
local previousKinds = ns.Defaults.townServiceKinds
ns.db.townServiceKinds = previousKinds
ns.SetTownServiceGroupShown(groups[1], true)
assert(ns.db.townServiceKinds ~= previousKinds and next(previousKinds) == nil,
 "saving a choice never mutates a defaults table shared by fresh profiles")
assert(ns.TownServiceGroupShown(groups[1]) and not ns.TownServiceGroupShown(groups[2]),
 "one profession can override the old preference")
assert(not ns.TownServiceFilterable({ key = "flight", section = "services" }),
 "flight points keep their own map controls")
assert(not ns.TownServiceFilterable({ key = "entrance:36", section = "entrances" }), "entrances are not town services")
print("service_filters_spec: passed")
]==]))()
