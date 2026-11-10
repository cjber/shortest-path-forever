---@class SPFNamespace
local ns = select(2, ...)
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
---@type string?
local target
-- The label of the running journey's target, which a renamed step may update in place.
---@type string?
local targetTitle
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
	target, targetTitle = nil, nil
	Restore()
end

-- The identity of a guide target: its map and position, not its step or label. Guidelime shifts a generated
-- target's coordinates as it re-places a quest objective, so the tenth of a map percent (about one yard in a zone)
-- decides whether the guide still points where our journey was planned to.
---@param map integer
---@param x number
---@param y number
---@return string
local function Key(map, x, y)
	return string.format("%d:%d:%d", map, math.floor(x * 10 + 0.5), math.floor(y * 10 + 0.5))
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
		target, targetTitle = nil, nil
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
	local title = Label(element)
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
		-- Guidelime decides when a step is complete, including its arrival radius; the journey holds the stop until
		-- the guide moves on to the next one.
		local started =
			API.NavigateRoute(OWNER, { { map = map, x = x / 100, y = y / 100, title = title, hold = true } })
		if not started then
			Clear()
			return
		end
		target, targetTitle = key, title
	end
	if API.CurrentStop(OWNER) then
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
	target, targetTitle = nil, nil
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
