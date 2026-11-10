---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local API = ShortestPathForever.API
local OWNER = "RestedXP"
---@type SPFRestedXP?
local hooked
---@type string?
local target
-- The label of the running journey's target, which a renamed step may update in place.
---@type string?
local targetTitle
-- The quests and action lines that label stands for, so a step that moved on at the same place updates the stop.
---@type string?
local targetQuests
-- Set while this file restarts guidance: RestedXP calls back into the hooks from inside that restart.
local navigating = false
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
	target, targetTitle, targetQuests = nil, nil, nil
	Restore()
end

-- The identity of a guide target: its map and position, not its step or label. RestedXP moves element.x and element.y
-- by less than the fraction of a percent between its own updates, so the tenth of a map percent (about one yard in a
-- zone) decides whether the guide still points where our journey was planned to.
local function Key(map, x, y)
	return string.format("%d:%d:%d", map, math.floor(x * 10 + 0.5), math.floor(y * 10 + 0.5))
end

-- The element tags RestedXP parses a quest into; the two action tags replace the quest's objectives with the action.
local QUEST_TAGS = { accept = true, complete = true, turnin = true, daily = true, dailyturnin = true, collect = true }

---@param element SPFRestedXPElement
---@return number[]? quests, string[]? actions, string key
local function StepQuests(element)
	local collector = ns.StepQuests()
	local function Add(part)
		if type(part) ~= "table" then
			return
		end
		if type(part.questIds) == "table" then
			for _, questID in ipairs(part.questIds) do
				collector.add(tonumber(questID))
			end
		end
		if not QUEST_TAGS[part.tag] then
			return
		end
		local action
		if part.tag == "accept" or part.tag == "daily" then
			action = "accept"
		elseif part.tag == "turnin" or part.tag == "dailyturnin" then
			action = "turnin"
		end
		collector.add(tonumber(part.questId), action)
	end
	Add(element)
	local step = type(element.step) == "table" and element.step or nil
	for _, part in ipairs(type(step) == "table" and type(step.elements) == "table" and step.elements or {}) do
		Add(part)
	end
	return collector.finish()
end

-- The current stop's label, renamed without replanning: a guide relabels its step as quests complete at one spot.
-- RestedXP splits a step into several stops at one place; they share the step's name.
local function Rename(title, map, x, y)
	local stop = API.CurrentStop(OWNER)
	if not stop or title == targetTitle or not API.RenameStop then
		return
	end
	targetTitle = title
	API.RenameStop(OWNER, stop, title, function(point)
		return point.map == map and point.x == x and point.y == y
	end)
end

local function Suppress()
	if not hooked then
		return
	end
	local frame = hooked.arrowFrame
	if textureShown == nil then
		textureShown, textShown = frame.texture:IsShown(), frame.text:IsShown()
		mouseEnabled = frame:IsMouseEnabled()
	end
	frame.texture:Hide()
	frame.text:Hide()
	frame:EnableMouse(false)
end

-- The arrow takeover alone: a player may keep RestedXP's arrow while still following its guide.
local function HoldArrow()
	if ns.db and ns.db.restedxpHideArrow == false then
		Restore()
	else
		Suppress()
	end
end

local function Integrated()
	local frontend = AdventureGuideForever and AdventureGuideForever.API
	return frontend ~= nil and type(frontend.RestedXPIntegrated) == "function" and frontend.RestedXPIntegrated() == true
end

local function Sync()
	if not hooked or not ns.db then
		return
	end
	-- Adventure Guide steering the guide hands us its step itself, and our arrow points at it: RestedXP's would be a
	-- second one, so it stays hidden. Adventure Guide's native UI choice leaves the guide, arrow and all, to RestedXP.
	if Integrated() then
		API.Cancel(OWNER)
		target, targetTitle, targetQuests = nil, nil, nil
		HoldArrow()
		return
	end
	local frontend = AdventureGuideForever and AdventureGuideForever.API
	if frontend and type(frontend.RestedXPNativeUI) == "function" and frontend.RestedXPNativeUI() then
		Clear()
		return
	end
	if not ns.db.restedxp or not ns.db.journey then
		Clear()
		return
	end
	-- Our own restart runs StartJourney, which RestedXP's hooks may observe; a second restart must never start inside it.
	if navigating then
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
	local quests, actions, questKey = StepQuests(element)
	local key = Key(map, x, y)
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
		navigating = true
		local started = API.NavigateRoute(OWNER, {
			{
				map = map,
				x = x / 100,
				y = y / 100,
				title = title,
				hold = true,
				questIDs = quests,
				tooltip = actions and table.concat(actions, "\n") or nil,
			},
		})
		navigating = false
		if not started then
			Clear()
			return
		end
		target, targetTitle, targetQuests = key, title, questKey
	end
	if API.CurrentStop(OWNER) then
		Rename(title, map, x / 100, y / 100)
		if questKey ~= targetQuests then
			targetQuests = questKey
			local index = API.CurrentStop(OWNER)
			if index then
				ns.SetStopQuests(OWNER, index, quests, actions)
			end
		end
		-- RestedXP owns the arrow when Shortest Path is not drawing one of its own.
		if ns.db.arrow ~= false then
			HoldArrow()
		else
			Restore()
		end
	else
		Restore()
	end
end

-- Let the player hand control back after pausing a guide, without waiting for its next native update.
function ns.ResumeRestedXP()
	local frontend = AdventureGuideForever and AdventureGuideForever.API
	if frontend and Integrated() and type(frontend.ResumeRestedXP) == "function" then
		frontend.ResumeRestedXP()
		return
	end
	target, targetTitle, targetQuests = nil, nil, nil
	Sync()
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
	if API.CurrentStop(OWNER) then
		return
	end
	if hooked and ns.db and Integrated() then
		HoldArrow()
	else
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
