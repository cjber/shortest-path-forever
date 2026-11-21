---@class SPFNamespace
local ns = select(2, ...)
if ns.broken then
	return
end

local L, Canvas = ns.L, ns.Canvas
local MAX_MARKS = 20
local PIN_SIZE = 20
local LABEL = {
	road = L["Mark: road missing here"],
	wall = L["Mark: wall here"],
}

---@class SPFMapReportPin : SPFCanvasPin
---@field mark SPFMapReportMark
---@field icon Texture
local Pin = CreateFromMixins(Canvas.PinMixin)

function Pin:OnLoad()
	self.takesMouse = true
	self:SetSize(PIN_SIZE, PIN_SIZE)
	self.icon = self:CreateTexture(nil, "ARTWORK")
	self.icon:SetPoint("BOTTOM", self, "CENTER")
	self:SetHitRectInsets(0, 0, -PIN_SIZE / 2, PIN_SIZE / 2)
	ns.Art.Icon(self.icon, ns.PIN_FILE, PIN_SIZE)
end

function Pin.ShouldMouseButtonBePassthrough(_, button)
	return button == "LeftButton" or button == "RightButton"
end

---@param mark SPFMapReportMark
function Pin:OnAcquired(mark)
	self.mark = mark
	if mark.kind == "wall" then
		self.icon:SetVertexColor(1, 0.4, 0.4)
	else
		self.icon:SetVertexColor(1, 1, 1)
	end
	self:SetPosition(mark.x, mark.y)
end

local function MenuHint()
	return L["%s-right-click the map to copy the report or clear its marks."]:format(ns.JourneyKeyName())
end

function Pin:OnMouseEnter()
	if GameTooltip:IsForbidden() then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, LABEL[self.mark.kind])
	GameTooltip_AddInstructionLine(GameTooltip, MenuHint())
	GameTooltip:Show()
end

function Pin:OnMouseLeave()
	if not GameTooltip:IsForbidden() and GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

---@type SPFCanvasPool
local pins

---@param mapID integer?
local function Draw(mapID)
	pins:ReleaseAll()
	for _, mark in ipairs(ns.charDB.mapReportMarks) do
		if mark.map == mapID then
			pins:Acquire(mark)
		end
	end
end

---@param entry ForeverMenuDescription
---@param text string
local function Explain(entry, text)
	entry:SetTooltip(function(tooltip)
		GameTooltip_AddNormalLine(tooltip, text)
	end)
end

---@param map SPFMapCanvas
---@param mapID integer?
---@param x number
---@param y number
---@return boolean
function ns.OpenMapReportMenu(map, mapID, x, y)
	local world = mapID and ns.WorldPoint(mapID, x, y)
	local marks = ns.charDB.mapReportMarks
	ForeverCore.ContextMenu(map, function(_, root)
		for _, kind in ipairs({ "road", "wall" }) do
			local entry = root:CreateButton(LABEL[kind], function()
				if not (mapID and world) then
					return
				end
				marks[#marks + 1] = { kind = kind, map = mapID, x = x, y = y, world = world }
				if #marks > MAX_MARKS then
					table.remove(marks, 1)
				end
				Draw(map:GetMapID())
			end)
			entry:SetEnabled(world ~= nil)
			Explain(
				entry,
				world and L["Save this spot in the report to help fix the walking map."]
					or L["This spot has no world coordinates. Choose another spot."]
			)
		end
		if #marks > 0 then
			Explain(
				root:CreateButton(L["Copy road and wall report"], function()
					ns.core.Report.Show(ns.MapReportText(marks))
				end),
				L["Open the report so you can copy and paste it into a bug report."]
			)
			Explain(
				root:CreateButton(L["Clear marks"], function()
					for i = #marks, 1, -1 do
						marks[i] = nil
					end
					Draw(map:GetMapID())
				end),
				L["Remove all saved road and wall marks from the map and report."]
			)
		end
	end)
	return true
end

ns.Init(function()
	pins = Canvas.Pool(WorldMapFrame, "mapReport", Pin)
	Canvas.Watch(WorldMapFrame, function(view, what)
		if what == "show" or what == "map" then
			Draw(view.mapID)
		end
	end)
end)
