---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local API = ShortestPathForever.API
local OWNER = "Guidelime"

-- Guidelime 6.017 (CurseForge 327139, 2026-11-05) publishes GuidelimeArrow, the frame its arrow draws from, but no
-- getter for the current step and no callback when it changes. Its element is
-- the current step's target, in percent coordinates, and the guide replaces it whenever its steps change. A slow
-- ticker reads it, which also notices the arrow when a guide is loaded after login; nothing of Guidelime's own
-- tables is touched.
local TICK = 0.5

---@type SPFGuidelimeArrow?
local hooked
-- The last target's rounded map and position, its element snapshot and the arrow setting, so an unchanged guide
-- stops before any label, quest or key string is built.
local targetMap, targetX, targetY
local targetElement, targetTitleRaw, targetElementCompleted, targetCompletedCount, targetAttached, targetAttachedTitle
local targetStep, targetElements, targetElementCount, targetArrow, targetRunning

-- Forget what the last tick saw, so the next one plans even at the same place.
local function ForgetTarget()
	targetMap, targetX, targetY = nil, nil, nil
	targetElement, targetTitleRaw, targetElementCompleted, targetCompletedCount = nil, nil, nil, nil
	targetAttached, targetAttachedTitle, targetStep, targetElements, targetElementCount, targetArrow, targetRunning =
		nil, nil, nil, nil, nil, nil, nil
end

-- The label of the running journey's target, which a renamed step may update in place.
---@type string?
local targetTitle
-- The quests and action lines that label stands for, so a step that moved on at the same place updates the stop.
---@type string?
local targetQuests
---@type number?
local savedAlpha
---@type boolean?
local savedMouse
---@type {Cancel: fun()}?
local ticker
local watcher = CreateFrame("Frame")

local function Restore()
	if hooked and savedAlpha ~= nil then
		hooked:SetAlpha(savedAlpha)
		hooked:EnableMouse(savedMouse == true)
		savedAlpha, savedMouse = nil, nil
	end
end

local function Clear()
	API.Cancel(OWNER)
	targetTitle, targetQuests = nil, nil
	ForgetTarget()
	Restore()
end

-- The identity of a guide target: its map and position, not its step or label. Guidelime shifts a generated
-- target's coordinates as it re-places a quest objective, so the tenth of a map percent (about one yard in a zone)
-- decides whether the guide still points where our journey was planned to.
---@param map integer
---@param x number
---@param y number
---@return integer, integer, integer
local function KeyParts(map, x, y)
	return map, math.floor(x * 10 + 0.5), math.floor(y * 10 + 0.5)
end

-- What the last Sync saw, compared field by field so a still guide allocates nothing on its ticker (#784). The
-- arrow's element is replaced when its step moves on; a step that merely relabels or completes a quest in place
-- changes one of these values.
---@param element SPFGuidelimeElement
---@return table, string?, boolean?, table?, string?, table?, table?, integer, integer
local function Snapshot(element)
	local attached = type(element.attached) == "table" and element.attached or nil
	local step = type(element.step) == "table" and element.step or nil
	local elements = step and type(step.elements) == "table" and step.elements or nil
	local completed = 0
	if element.completed then
		completed = completed + 1
	end
	if attached and attached.completed then
		completed = completed + 1
	end
	if elements then
		for _, part in ipairs(elements) do
			if type(part) == "table" and part.completed then
				completed = completed + 1
			end
		end
	end
	return element,
		type(element.title) == "string" and element.title or nil,
		element.completed,
		attached,
		attached and type(attached.title) == "string" and attached.title or nil,
		step,
		elements,
		completed,
		elements and #elements or 0
end

-- The current stop's label, renamed without replanning: a guide relabels its step as quests complete at one spot.
-- A guide whose generated target jitters within the key's tolerance still relabels the one stop under way.
---@param title string
local function Rename(title)
	local stop = API.CurrentStop(OWNER)
	if not stop or title == targetTitle then
		return
	end
	targetTitle = title
	API.RenameStop(OWNER, stop, title)
end

-- The step text carries the guide's colour and icon markup; the tracker wants the words alone.
---@param text string
---@return string
local function Clean(text)
	text = text:gsub("|c%x+", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("[\r\n]+", " ")
	return (text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The element types Guidelime parses a quest into; its own step text names the quest for each of them.
local QUEST_TYPES = { ACCEPT = true, COMPLETE = true, TURNIN = true, WORK = true, SKIP = true, PICKUP = true }

-- The quest's name as Guidelime prints it: the guide's own title when it gives one, else the client's.
---@param element SPFGuidelimeElement
---@return string?
local function QuestName(element)
	local title = element.title
	if type(title) == "string" and Clean(title) ~= "" then
		return Clean(title)
	end
	local questID = tonumber(element.questId)
	if questID and C_QuestLog and type(C_QuestLog.GetTitleForQuestID) == "function" then
		local name = C_QuestLog.GetTitleForQuestID(questID)
		if type(name) == "string" and Clean(name) ~= "" then
			return Clean(name)
		end
	end
	return nil
end

-- The words one parsed element contributes, as Guidelime's own step text gathers them: the guide's text where it
-- wrote any, else the quest, item or target it names. APPLIES and the other wordless codes contribute nothing.
---@param element SPFGuidelimeElement
---@return string?
local function Words(element)
	local text = element.text
	if type(text) == "string" and Clean(text) ~= "" then
		return Clean(text)
	end
	if QUEST_TYPES[element.t] and element.questId ~= nil then
		return QuestName(element)
	end
	if element.t == "TARGET" or element.t == "USE_ITEM" or element.t == "COLLECT_ITEM" then
		local title = element.title
		if type(title) == "string" and Clean(title) ~= "" then
			return Clean(title)
		end
	end
	return nil
end

-- What to call the step in the tracker: the arrow's own title when it has one, else the step's parsed parts. The raw
-- line still holds Guidelime's codes ([QA96394], [TAR264943]), so it is never read.
---@param element SPFGuidelimeElement
---@return string
local function Label(element)
	local attached = element.attached
	local title = type(attached) == "table" and attached.title or nil
	if type(title) ~= "string" or Clean(title) == "" then
		title = element.title
	end
	if type(title) == "string" and Clean(title) ~= "" then
		return Clean(title)
	end
	local step = element.step
	local elements = type(step) == "table" and step.elements or nil
	if type(elements) ~= "table" then
		return "Guidelime"
	end
	local parts = {}
	for _, part in ipairs(elements) do
		local words = Words(part)
		if words then
			parts[#parts + 1] = words
		end
	end
	if #parts == 0 then
		return "Guidelime"
	end
	return Clean(table.concat(parts, " "))
end

-- The arrow's element is the step's target: the quest itself, the target attached to it, or a goto inside its step.
---@param element SPFGuidelimeElement
---@return number[]? quests, string[]? actions, string key
local function StepQuests(element)
	local collector = ns.StepQuests()
	local function Add(part)
		if type(part) ~= "table" or not QUEST_TYPES[part.t] then
			return
		end
		local action = part.t == "ACCEPT" and "accept" or part.t == "TURNIN" and "turnin" or nil
		collector.add(tonumber(part.questId), action, action and QuestName(part) or nil)
	end
	Add(element)
	Add(element.attached)
	local step = type(element.step) == "table" and element.step or nil
	for _, part in ipairs(type(step) == "table" and type(step.elements) == "table" and step.elements or {}) do
		Add(part)
	end
	return collector.finish()
end

-- Guidelime's arrow steps aside while ours draws, the way RestedXP's does. Guidelime resets its arrow's alpha only
-- when it creates the frame, so fading the frame keeps every part of it, text included, out of the way without
-- touching the player's guide settings.
local function Suppress()
	local frame = GuidelimeArrow
	if not frame then
		return
	end
	if hooked and frame ~= hooked then
		Restore()
	end
	if savedAlpha == nil then
		hooked = frame
		savedAlpha = frame:GetAlpha()
		savedMouse = frame:IsMouseEnabled()
	end
	frame:SetAlpha(0)
	frame:EnableMouse(false)
end

local function Stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

---@param value any
---@return boolean
local function Number(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Sync()
	if not (ns.db and ns.db.guidelime and ns.db.journey) then
		Clear()
		Stop()
		return
	end
	local arrow = GuidelimeArrow
	if not arrow then
		Clear()
		return
	end
	-- Adventure Guide's own journey and RestedXP's step lead when either is running: following a second guide back
	-- and forth would replan the same route on every step. The player's own journey is replaced by a new step, as
	-- with RestedXP, and *Resume guide* takes the guide back at any time. Our arrow still points at the leading
	-- guide's step, so Guidelime's arrow stays out of the way while we draw one.
	local owner = ns.JourneyOwner()
	if owner and owner ~= OWNER and (owner == "RestedXP" or owner == "AdventureGuideForever") then
		targetTitle, targetQuests = nil, nil
		ForgetTarget()
		if ns.db.arrow ~= false then
			Suppress()
		else
			Restore()
		end
		return
	end
	local element = arrow.element
	if not element or element.completed then
		Clear()
		return
	end
	local map, x, y = element.mapID, element.x, element.y
	if
		not Number(map)
		or map <= 0
		or map % 1 ~= 0
		or not Number(x)
		or not Number(y)
		or x < 0
		or x > 100
		or y < 0
		or y > 100
	then
		Clear()
		return
	end
	---@cast map integer
	---@cast x number
	---@cast y number
	local kMap, kX, kY = KeyParts(map, x, y)
	local elem, titleRaw, elementCompleted, attached, attachedTitle, step, elements, completedCount, elementCount =
		Snapshot(element)
	local arrowOn = ns.db.arrow ~= false
	local running = API.CurrentStop(OWNER) ~= nil
	local samePlace = kMap == targetMap and kX == targetX and kY == targetY
	local unchanged = samePlace
		and elem == targetElement
		and titleRaw == targetTitleRaw
		and elementCompleted == targetElementCompleted
		and completedCount == targetCompletedCount
		and attached == targetAttached
		and attachedTitle == targetAttachedTitle
		and step == targetStep
		and elements == targetElements
		and elementCount == targetElementCount
		and arrowOn == targetArrow
		and running == targetRunning
	if InCombatLockdown() then
		if not samePlace then
			API.Cancel(OWNER)
			Restore()
		end
		watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	-- Nothing the guide or our setting shows has changed since the last tick: no label, quest collector or key is
	-- built, so the ticker allocates nothing while the player stands on the same step (#784).
	if unchanged then
		return
	end
	local title = Label(element)
	local quests, actions, questKey = StepQuests(element)
	if not samePlace then
		-- Guidelime decides when a step is complete, including its arrival radius; the journey holds the stop until
		-- the guide moves on to the next one.
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
		if not started then
			Clear()
			return
		end
		targetTitle, targetQuests = title, questKey
	elseif questKey ~= targetQuests then
		-- The step moved on at the same place (a turn-in at the NPC just left): only its quests changed, so the stop
		-- gets the new live objectives without the route being planned again.
		targetQuests = questKey
		local stop = API.CurrentStop(OWNER)
		if stop then
			ns.SetStopQuests(OWNER, stop, quests, actions)
		end
	end
	targetMap, targetX, targetY = kMap, kX, kY
	targetElement, targetTitleRaw, targetElementCompleted, targetCompletedCount =
		elem, titleRaw, elementCompleted, completedCount
	targetAttached, targetAttachedTitle = attached, attachedTitle
	running = API.CurrentStop(OWNER) ~= nil
	targetStep, targetElements, targetElementCount, targetArrow, targetRunning =
		step, elements, elementCount, arrowOn, running
	if running then
		Rename(title)
		-- Guidelime owns the arrow when Shortest Path is not drawing one of its own.
		if ns.db.arrow ~= false then
			Suppress()
		else
			Restore()
		end
	else
		Restore()
	end
end

local function Start()
	if ticker or not (C_Timer and type(C_Timer.NewTicker) == "function") then
		return
	end
	ticker = C_Timer.NewTicker(TICK, Sync)
end

-- Let the player hand control back after pausing a guide, without waiting for its next step.
function ns.ResumeGuidelime()
	targetTitle, targetQuests = nil, nil
	ForgetTarget()
	Sync()
end

-- The setting, Guidelime loading and the addon's own load all call this.
function ns.RefreshGuidelime()
	if type(Guidelime) == "table" and ns.db and ns.db.guidelime and ns.db.journey then
		Start()
	else
		Stop()
	end
	Sync()
end

hooksecurefunc(ns, "JourneyChanged", function()
	if API.CurrentStop(OWNER) then
		return
	end
	Restore()
end)

ns.Init(function()
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:RegisterEvent("PLAYER_LOGIN")
	watcher:SetScript("OnEvent", function(self, event, name)
		if event == "PLAYER_REGEN_ENABLED" then
			self:UnregisterEvent(event)
			Sync()
		elseif event == "PLAYER_LOGIN" then
			ns.RefreshGuidelime()
		elseif
			event == "ADDON_LOADED"
			and type(name) == "string"
			and (name == "Guidelime" or name:match("^Guidelime_"))
		then
			ns.RefreshGuidelime()
		end
	end)
	ns.RefreshGuidelime()
end)
