---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The player's own journey survives a reload or relog. Its goal or remaining stops are kept in charDB.journey and
-- started again once the world is up and combat is over. Addons that own their journeys start them again themselves.
-- Any journey started by then wins and the kept one is dropped. Otherwise it is kept until it ends or you clear it.

-- Seconds after the loading screen, so owners and TomTom's restored arrow can start theirs first.
local SETTLE = 2

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
---@type (SPFKeptJourney|SPFKeptStops)?
local kept
local entered, settled = false, false
---@type {owner: string, stops: SPFAPIStop[]}?
local itinerary

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
	if point and itinerary and owner == itinerary.owner then
		local index = ShortestPathForever.API.CurrentStop(itinerary.owner)
		if index then
			local remaining = {}
			for i = index, #itinerary.stops do
				remaining[#remaining + 1] = itinerary.stops[i]
			end
			ns.charDB.journey = { stops = remaining }
			return
		end
	end
	itinerary = nil
	if not point or not ns.IsPlayerJourney(owner) then
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

-- The editor hands over its validated submission once the API accepts it. A same-place handover can
-- change owners without calling JourneyChanged, so keep it here as well as when its stop advances.
---@param owner string
---@param stops SPFAPIStop[]
function ns.KeepJourneyStops(owner, stops)
	itinerary = { owner = owner, stops = stops }
	Keep(ns.JourneyGoal())
end

hooksecurefunc(ns, "JourneyChanged", Keep) -- taint-ok: ns is this addon's own namespace table.

-- A journey the player is starting replaces the one waiting to resume.
function ns.ForgetKeptJourney()
	kept = nil
end

local frame

-- The kept journey was started or dropped.
local function Done()
	frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
	frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

-- Starts the kept journey, or forgets it when Journeys are off or another journey is under way. A stops route the API
-- refuses for now, as in a dungeon where you have no position, waits for a later loading screen or end of combat.
local function Resume()
	local resume = kept
	if not (resume and settled) or InCombatLockdown() then
		return
	end
	local wanted = ns.db.journey and not ns.JourneyGoal()
	if wanted and resume.stops ~= nil and ns.JourneyStopsEditor.Restore(resume.stops) == false then
		return
	end
	kept = nil
	Done()
	if ns.charDB.journey == resume then
		ns.charDB.journey = nil
	end
	if not wanted or resume.stops ~= nil then
		return
	end
	---@cast resume SPFKeptJourney
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
	frame:RegisterEvent("PLAYER_LOGOUT")
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			Resume()
		elseif event == "PLAYER_LOGOUT" then
			-- A same-place handover to another owner can leave the goal unchanged.
			if itinerary then
				Keep(ns.JourneyGoal())
			end
		elseif not entered then
			-- The loading screen that ends a login or reload takes the kept journey.
			entered = true
			local journey = ns.charDB.journey
			kept = type(journey) == "table" and journey or nil
			if not kept then
				ns.charDB.journey = nil
				Done()
				return
			end
			frame:RegisterEvent("PLAYER_REGEN_ENABLED")
			C_Timer.After(SETTLE, function()
				settled = true
				Resume()
			end)
		elseif kept then
			C_Timer.After(SETTLE, Resume)
		end
	end)
end)
