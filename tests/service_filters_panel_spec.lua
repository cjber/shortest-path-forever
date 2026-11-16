-- Reuse the panel's client fixture, adding the real shared filter lookup and native checkbox state.
local file = assert(io.open("tests/services_panel_spec.lua"))
local source = file:read("*a")
file:close()
source = source:gsub(
	"env%._G = env",
	[[
ns.Canvas = { PinMixin = {} }
env.CreateFromMixins = function() return {} end
setfenv(assert(loadfile("UI/NearbyProfessions.lua")), env)("ShortestPathForever", ns)
setfenv(assert(loadfile("UI/TownServices.lua")), env)("ShortestPathForever", ns)
env._G = env]],
	1
)
assert(loadstring(source .. [==[
ns.NearbyServices.State = function() return "ready" end
search:SetText("")
ns.RefreshServiceFilters()
local function ordinaryRow(key)
 for _, row in ipairs(created) do
  if row.key == key and row.Filter and row:IsShown() then return row end
 end
end
local arrow = assert(ordinaryRow("arrows"))
assert(arrow.Filter:IsShown() and arrow.Filter:GetChecked(), "ordinary service has a checked map switch")
local before = navigated
scroll:SetVerticalScroll(42)
arrow.Filter:SetChecked(false)
arrow.Filter.scripts.OnClick(arrow.Filter)
assert(ns.db.townServiceKinds.arrows == false, "row click stores the exact service key")
assert(navigated == before, "checkbox does not start a journey")
assert(scroll:GetVerticalScroll() == 42, "filter changes preserve scroll")
ns.SetTownServiceGroupShown(groups[1], true)
assert(arrow.Filter:GetChecked(), "map-menu changes immediately repaint visible checkboxes")
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
print("service_filters_panel_spec: passed")
]==]))()
