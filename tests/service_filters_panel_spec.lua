-- Reuse the panel's client fixture, adding the real shared filter lookup and native checkbox state.
local file = assert(io.open("tests/services_panel_spec.lua"))
local source = file:read("*a")
file:close()
source = source:gsub(
	"env%._G = env",
	[[
ns.Canvas = { PinMixin = {} }
env.CreateFromMixins = function() return {} end
ns.SetOption = function(key, value) ns.db[key] = value end
setfenv(assert(loadfile("UI/NearbyProfessions.lua")), env)("ShortestPathForever", ns)
setfenv(assert(loadfile("UI/TownServices.lua")), env)("ShortestPathForever", ns)
env._G = env]],
	1
)
assert(loadstring(source .. [==[
ns.NearbyServices.State = function() return "ready" end
ns.NearbyServices.Groups = function() return groups end
search:SetText("")
ns.RefreshServiceFilters()
local function ordinaryRow(key)
 for _, row in ipairs(created) do
  if row.key == key and row.Filter and row:IsShown() then return row end
 end
end
local arrow = assert(ordinaryRow("arrows"))
-- The town services layer is off by default: no row is on the map, so none shows ticked (#1067).
assert(arrow.Filter:IsShown() and not arrow.Filter:GetChecked(), "a row is unticked while its pins are off the map")
arrow.Filter:SetChecked(true)
arrow.Filter.scripts.OnClick(arrow.Filter)
assert(ns.db.townServices == "all", "ticking a row turns the town services layer on")
assert(ns.db.townServiceKinds.arrows == true and ns.db.townServiceKinds.bank == false,
 "the layer comes on with only the ticked service")
assert(arrow.Filter:GetChecked(), "the ticked row stays ticked")
ns.db.townServices = "off"
ns.RefreshTownServices()
assert(not arrow.Filter:GetChecked(), "turning the layer off repaints the row unticked")
ns.db.townServices = "all"
ns.RefreshTownServices()
assert(arrow.Filter:GetChecked(), "turning the layer on repaints the row ticked")
local before = navigated
scroll:SetVerticalScroll(42)
arrow.Filter:SetChecked(false)
arrow.Filter.scripts.OnClick(arrow.Filter)
assert(ns.db.townServiceKinds.arrows == false, "row click stores the exact service key")
assert(navigated == before, "checkbox does not start a journey")
assert(scroll:GetVerticalScroll() == 42, "filter changes preserve scroll")
ns.SetTownServiceGroupShown(groups[1], true)
assert(arrow.Filter:GetChecked(), "map-menu changes immediately repaint visible checkboxes")
ns.SetTownServiceGroupShown(groups[2], true)
search:SetText("bank")
local bank = assert(ordinaryRow("bank"))
assert(bank == arrow and bank.Filter:GetChecked(), "a recycled row reads its new kind")
bank.Filter:SetChecked(false)
bank.Filter.scripts.OnClick(bank.Filter)
assert(ns.db.townServiceKinds.bank == false and ns.db.townServiceKinds.arrows == true,
 "a recycled checkbox changes its current group")
search:SetText("Deadmines")
local entrance = assert(ordinaryRow("entrance:36"))
assert(entrance == bank and not entrance.Filter:IsShown() and not entrance.Filter:GetChecked(),
 "recycling a row for an entrance clears the service checkbox")
local sections = ns.NearbyServices.Sections
local lastCollapsed
ns.NearbyServices.Sections = function(world, query, collapsed, estimates)
 lastCollapsed = collapsed
 return sections(world, query, collapsed, estimates)
end
search:SetText("class")
local header
for _, row in ipairs(created) do
 if row.CollapseButton and row:IsShown() then header = row; break end
end
assert(header and header.key == "trainers", "recycled section header takes its current key")
header.scripts.OnClick(header)
assert(lastCollapsed.trainers and not lastCollapsed.vendors, "recycled header collapses its current section")
-- The flight master row shows and hides the flight master pins, which stand for its NPCs on the map (#1068).
groups[#groups + 1] = { section = "vendors", key = "flight", label = "Flight master", icon = 2512 }
places.flight = { { id = 5, name = "Dungar Longdrink", title = "Gryphon Master", map = 100, x = 0.4, y = 0.4 } }
ns.db.mapFlightMasters = true
search:SetText("flight")
local flight = assert(ordinaryRow("flight"))
assert(flight.Filter:IsShown() and flight.Filter:GetChecked(), "the flight master row has a ticked map checkbox")
flight.Filter:SetChecked(false)
flight.Filter.scripts.OnClick(flight.Filter)
assert(ns.db.mapFlightMasters == false, "unticking the flight master row hides the flight master pins")
assert(ns.db.townServiceKinds.flight == nil, "the flight master is not a town service filter")
ns.db.mapFlightMasters = true
ns.RefreshServiceFilters()
assert(flight.Filter:GetChecked(), "a repaint reads the saved flight master choice")
print("service_filters_panel_spec: passed")
]==]))()
