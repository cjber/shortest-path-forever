---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

-- The lines under the arrow and the arrival pin: a caller's own details when it gave any (Adventure Guide), otherwise
-- the live objectives of the quests the stop names, read from the client's quest log. Nothing is copied from a guide,
-- so a step that moved on without moving the player never shows the objectives of the quest it stood for before.

-- A positive whole quest id, or nil for anything else: the one check every quest source uses.
---@param value any
---@return integer?
function ns.QuestID(value)
	if not canaccessvalue(value) or type(value) ~= "number" then
		return nil
	end
	if value ~= value or math.abs(value) == math.huge or value % 1 ~= 0 or value < 1 then
		return nil
	end
	return value
end

-- The client's own wording, where it has one, so the pin reads like the tracker.
---@return string
local function Ready()
	local client = rawget(getfenv(), "QUEST_WATCH_QUEST_READY") or rawget(_G, "QUEST_WATCH_QUEST_READY")
	return client or L["Ready for turn-in"]
end

-- A finished objective reads in the colour the tracker gives a completed line.
---@param text string
---@return string
local function Complete(text)
	-- The tracker palette adds Complete beside the annotated Normal, Highlight and Header fields.
	local color = OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR.Complete --[[@as colorRGBA?]]
	if not (color and type(color.r) == "number" and type(CreateColor) == "function") then
		return text
	end
	return CreateColor(color.r, color.g, color.b):WrapTextInColorCode(text)
end

-- Whether the client counts an objective as done, preferring its own answer over the counters.
---@param objective table
---@return boolean
local function Finished(objective)
	if objective.finished ~= nil then
		return objective.finished == true
	end
	local done, required = tonumber(objective.numFulfilled), tonumber(objective.numRequired)
	return done ~= nil and required ~= nil and done >= required
end

-- One quest's live lines: its objectives, a done one marked, and a quest with nothing left to do reading as ready to
-- turn in. Nil when the client has no objectives for it: a quest not in the log, or one whose data is not cached yet
-- (the next QUEST_LOG_UPDATE asks again).
---@param questID integer
---@return string[]?
local function QuestLines(questID)
	local get = C_QuestLog and C_QuestLog.GetQuestObjectives
	if type(get) ~= "function" then
		return nil
	end
	local objectives = get(questID)
	if not (canaccessvalue(objectives) and type(objectives) == "table") then
		return nil
	end
	local complete = #objectives > 0
	for _, objective in ipairs(objectives) do
		if not (canaccessvalue(objective) and type(objective) == "table" and Finished(objective)) then
			complete = false
		end
	end
	if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) == true then
		complete = true
	end
	local lines = {}
	-- The ready line first: with the arrow's few lines, "nothing left to do" must not be the line that is cut.
	if complete then
		lines[1] = Ready()
	end
	for _, objective in ipairs(objectives) do
		if canaccessvalue(objective) and type(objective) == "table" then
			local text = objective.text
			if type(text) == "string" and text ~= "" then
				lines[#lines + 1] = Finished(objective) and Complete(text) or text
			end
		end
	end
	return lines[1] and lines or nil
end

-- The lines for a stop: its own details when the caller gave any, else its quests' live objectives in order.
---@param stop table?
---@return string[]?
function ns.StopObjectiveLines(stop)
	if type(stop) ~= "table" then
		return nil
	end
	local details = stop.details
	if type(details) == "table" then
		local lines = {}
		for _, line in ipairs(details) do
			if type(line) == "string" and line ~= "" then
				lines[#lines + 1] = line
			end
		end
		if lines[1] then
			return lines
		end
	end
	local quests = stop.questIDs
	if type(quests) ~= "table" then
		local questID = ns.QuestID(stop.questID)
		quests = questID and { questID } or nil
	end
	if not quests then
		return nil
	end
	local lines = {}
	for _, value in ipairs(quests) do
		local questID = ns.QuestID(value)
		for _, line in ipairs(questID and QuestLines(questID) or {}) do
			lines[#lines + 1] = line
		end
	end
	return lines[1] and lines or nil
end

---@class SPFStepQuests
---@field add fun(questID: any, action?: "turnin"|"accept", name?: string)
---@field finish fun(): number[]?, string[]?, string

-- Collects one guide step's quests and action lines, so every bridge reports them the same way.
---@return SPFStepQuests
function ns.StepQuests()
	local quests, actions = {}, {}
	local seen, actionSeen = {}, {}
	local nonAction = false
	local collector = {}
	function collector.add(questID, action, name)
		local id = ns.QuestID(questID)
		if not id then
			return
		end
		if not seen[id] then
			seen[id] = true
			quests[#quests + 1] = id
		end
		if action ~= "turnin" and action ~= "accept" then
			nonAction = true
			return
		end
		if actionSeen[id] then
			return
		end
		actionSeen[id] = true
		local title = name
		if title == nil then
			title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
			title = canaccessvalue(title) and title or nil
		end
		if type(title) == "string" and title ~= "" then
			actions[#actions + 1] = (action == "turnin" and L["%s (turn in)"] or L["%s (pick up)"]):format(title)
		end
	end
	function collector.finish()
		local details = not nonAction and actions[1] ~= nil and actions or nil
		local list = quests[1] and quests or nil
		local key = (list and table.concat(list, ",") or "") .. "|" .. (details and table.concat(details, "\n") or "")
		return list, details, key
	end
	return collector
end
