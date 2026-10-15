---@class SPFNamespace
local ns = select(2, ...)

-- With "Keep journeys after a reload" on, a journey you planned yourself (a map or minimap click, /way, a quest,
-- Nearby services) survives a /reload or logging back in: its goal is kept in charDB.journey and started again once
-- the world is up and combat is over. Addons that own their journeys (Adventure Guide, TomTom's arrow, RestedXP,
-- Polestar through the API) start theirs again themselves and go first: any journey under way by then wins and the
-- kept one is dropped. Kept for half an hour.

local KEEP = 30 * 60
-- Seconds after the loading screen, so owners and TomTom's restored arrow can start theirs first.
local SETTLE = 2

---@param point SPFPoint?
local function Keep(point)
	if not (ns.db and ns.charDB) then
		return
	end
	if not (point and ns.db.resumeJourney and not ns.JourneyOwner()) then
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
		pinBadge = point.pinBadge or nil,
		at = GetServerTime(),
	}
end

hooksecurefunc(ns, "JourneyChanged", Keep) -- taint-ok: ns is this addon's own namespace table.

-- The journey kept from before the reload, taken at its loading screen; a journey started since saves over
-- charDB.journey and is left alone.
---@type SPFKeptJourney?
local kept

-- Starts the kept journey, or forgets it when it is too old, turned off, or another journey started first.
local function Resume()
	local resume = kept
	if not resume or InCombatLockdown() then
		return
	end
	kept = nil
	if ns.charDB.journey == resume then
		ns.charDB.journey = nil
	end
	local age = GetServerTime() - (tonumber(resume.at) or 0)
	if not (ns.db.resumeJourney and ns.db.journey) or ns.HasJourney() or age < 0 or age > KEEP then
		return
	end
	local map, x, y = tonumber(resume.map), tonumber(resume.x), tonumber(resume.y)
	if not (map and x and y) then
		return
	end
	ns.StartJourney({
		map = map,
		x = x,
		y = y,
		z = tonumber(resume.z),
		label = type(resume.label) == "string" and resume.label or nil,
		questID = tonumber(resume.questID),
		pinBadge = resume.pinBadge == true or nil,
	})
end

ns.Init(function()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	local entered = false
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			Resume()
		elseif not entered then
			-- Only the loading screen that ends a login or reload: later ones keep the journey running anyway.
			entered = true
			local journey = ns.charDB.journey
			kept = type(journey) == "table" and journey or nil
			if kept then
				C_Timer.After(SETTLE, Resume)
			end
		end
	end)
end)
