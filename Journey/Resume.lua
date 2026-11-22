---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- A journey you planned yourself (a map or minimap click, /way, a quest,
-- Nearby services) survives a /reload or logging back in: its goal is kept in charDB.journey and started again once
-- the world is up and combat is over. Addons that own their journeys (Adventure Guide, TomTom's arrow, RestedXP,
-- Polestar through the API) start theirs again themselves and go first: any journey started by then wins and the
-- kept one is dropped. It is kept until it ends or you clear it.

-- Seconds after the loading screen, so owners and TomTom's restored arrow can start theirs first.
local SETTLE = 2
-- Nearby services starts its journeys through the API under this addon's own name: those are the player's too.
local OWN = "Shortest Path Forever"

---@param value any
---@return number?
local function Finite(value)
	value = tonumber(value)
	return value and value == value and math.abs(value) < math.huge and value or nil
end

-- The hand-in quests a kept journey carries: a list of positive whole quest IDs, copied, as the API validates it.
-- Anything else is dropped rather than resumed as a damaged entry.
---@param list any
---@return number[]?
local function Handins(list)
	if type(list) ~= "table" then
		return nil
	end
	local count = #list
	if count < 1 then
		return nil
	end
	local copy = {}
	for key, questID in pairs(list) do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
			return nil
		end
		if type(questID) ~= "number" or questID ~= questID or questID % 1 ~= 0 or questID < 1 then
			return nil
		end
		copy[key] = questID
	end
	return copy
end

-- The journey kept from before the reload, taken at its loading screen. It waits for the owners, then for combat to
-- end, and is dropped as soon as any other journey starts or ends.
---@type SPFKeptJourney?
local kept
local entered, settled = false, false

---@param point SPFPoint?
local function Keep(point)
	-- Anything that changes guidance after the loading screen overrides what was kept from before it.
	if entered then
		kept = nil
	end
	if not (ns.db and ns.charDB) then
		return
	end
	local owner = ns.JourneyOwner()
	if not (point and (owner == nil or owner == OWN)) then
		ns.charDB.journey = nil
		return
	end
	local label = point.label
	ns.charDB.journey = {
		map = point.map,
		x = point.x,
		y = point.y,
		z = point.z,
		label = canaccessvalue(label) and type(label) == "string" and label or nil,
		questID = point.questID,
		handins = Handins(point.handins),
	}
end

hooksecurefunc(ns, "JourneyChanged", Keep) -- taint-ok: ns is this addon's own namespace table.

local frame

-- The one attempt is over.
local function Done()
	frame:UnregisterAllEvents()
end

-- Starts the kept journey, or forgets it when Journeys are off or another journey is under way.
local function Resume()
	local resume = kept
	if not (resume and settled) or InCombatLockdown() then
		return
	end
	kept = nil
	Done()
	if ns.charDB.journey == resume then
		ns.charDB.journey = nil
	end
	if not ns.db.journey or ns.JourneyGoal() then
		return
	end
	local map, x, y = Finite(resume.map), Finite(resume.x), Finite(resume.y)
	if not (map and x and y) then
		return
	end
	-- Behind a corpse run, StartJourney queues it for when you are alive again.
	ns.StartJourney({
		map = map,
		x = x,
		y = y,
		z = Finite(resume.z),
		label = type(resume.label) == "string" and resume.label or nil,
		questID = Finite(resume.questID),
		handins = Handins(resume.handins),
	})
end

ns.Init(function()
	frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			Resume()
		elseif not entered then
			-- Only the loading screen that ends a login or reload: later ones keep the journey running anyway.
			entered = true
			local journey = ns.charDB.journey
			kept = type(journey) == "table" and journey or nil
			if not kept then
				Done()
				return
			end
			frame:RegisterEvent("PLAYER_REGEN_ENABLED")
			C_Timer.After(SETTLE, function()
				settled = true
				Resume()
			end)
		end
	end)
end)
