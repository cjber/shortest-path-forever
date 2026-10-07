---@class SPFNamespace
local ns = select(2, ...)
local API = ShortestPathForever.API
local OWNER = "RestedXP"
---@type SPFRestedXP?
local hooked
---@type string?
local target
---@type boolean?
local textureShown
---@type boolean?
local textShown
---@type boolean?
local mouseEnabled
local watcher = CreateFrame("Frame")

local function Restore()
	if hooked and textureShown ~= nil then
		hooked.arrowFrame.texture:SetShown(textureShown)
		hooked.arrowFrame.text:SetShown(textShown == true)
		hooked.arrowFrame:EnableMouse(mouseEnabled == true)
		textureShown, textShown, mouseEnabled = nil, nil, nil
	end
end

local function Clear()
	API.Cancel(OWNER)
	target = nil
	Restore()
end

local function Sync()
	if not hooked or not ns.db then
		return
	end
	if not ns.db.restedxp or not ns.db.journey then
		Clear()
		return
	end
	local frame = hooked.arrowFrame
	local element = frame.element
	local profile = hooked.settings and hooked.settings.profile
	if
		not hooked.currentGuide
		or (hooked.hideArrow and not frame.wrongContinent)
		or not profile
		or profile.showEnabled == false
		or not element
		or not hooked.activeWaypoints
		or #hooked.activeWaypoints == 0
	then
		Clear()
		return
	end
	local step = element.step
	if
		not step
		or not step.active
		or not element.arrow
		or element.skip
		or element.hidden
		or (element.generated and element.generated ~= 0)
		or (element.parent and (element.parent.completed or element.parent.skip))
		or (element.text and element.completed)
	then
		Clear()
		return
	end
	local map, x, y = element.zone, element.x, element.y
	if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
		Clear()
		return
	end
	local title = (element.title or step.arrowtext or step.title or "RestedXP"):gsub("RXP_[A-Z]+_", "")
	local key = string.format("%s:%.17g:%.17g:%s", map, x, y, tostring(step.index))
	if InCombatLockdown() then
		if key ~= target then
			API.Cancel(OWNER)
			Restore()
		end
		watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if key ~= target then
		-- RestedXP decides when an interaction or waypoint is complete, including large arrival radii.
		if not API.NavigateRoute(OWNER, { { map = map, x = x / 100, y = y / 100, title = title, hold = true } }) then
			Clear()
			return
		end
		target = key
	end
	if API.CurrentStop(OWNER) then
		if textureShown == nil then
			textureShown, textShown = frame.texture:IsShown(), frame.text:IsShown()
			mouseEnabled = frame:IsMouseEnabled()
		end
		-- Preserve the frame's visibility and alpha: RestedXP updates both during guidance.
		frame.texture:Hide()
		frame.text:Hide()
		frame:EnableMouse(false)
	else
		Restore()
	end
end

function ns.RefreshRestedXP()
	local rxp = RXP
	if
		not hooked
		and rxp
		and rxp.arrowFrame
		and type(rxp.UpdateMap) == "function"
		and type(rxp.UpdateGotoSteps) == "function"
	then
		hooked = rxp
		hooksecurefunc(rxp, "UpdateMap", Sync) -- taint-ok: RestedXP owns this addon table.
		hooksecurefunc(rxp, "UpdateGotoSteps", Sync) -- taint-ok: RestedXP owns this addon table.
		if type(rxp.ResetArrowPosition) == "function" then
			hooksecurefunc(rxp, "ResetArrowPosition", Sync) -- taint-ok: RestedXP owns this addon table.
		end
	end
	Sync()
end

hooksecurefunc(ns, "JourneyChanged", function()
	if not API.CurrentStop(OWNER) then
		Restore()
	end
end)

ns.Init(function()
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:SetScript("OnEvent", function(self, event, name)
		if event == "PLAYER_REGEN_ENABLED" then
			self:UnregisterEvent(event)
			Sync()
		elseif name == "RXPGuides" then
			ns.RefreshRestedXP()
		end
	end)
	ns.RefreshRestedXP()
end)
