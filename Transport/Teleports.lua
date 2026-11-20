---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The personal teleports this character can cast now, for the planner. The client names the bind point but has no
-- position for it, so it is where you stood when you bound (beside the innkeeper), or where a Hearthstone or Astral
-- Recall last set you down, kept with that name. Bound anywhere else since (before this addon, or on another
-- client), the names disagree: no bind teleport until you bind or hearth again.

local places, placesKey, sources = {}, nil, {}
-- Both switches off: no teleports for any caller.
local NONE = {}
-- The Hearthstone itself; its own switch also keeps the other bind teleport, Astral Recall, out of journeys.
local HEARTHSTONE = 6948

-- The Hearthstone and Astral Recall land at the bind point, so the saved Use Hearthstone switch covers them both, while
-- class teleports keep their own switch (Core/Core.lua). Each defaults on.
---@return boolean
local function HearthAllowed()
	return ns.db == nil or ns.db.useHearthstone ~= false
end

---@return boolean
local function ClassTeleportsAllowed()
	return ns.db == nil or ns.db.teleports ~= false
end

---@return SPFBindPoint?
local function Bind()
	local bind, name = ns.charDB.bind, GetBindLocation()
	if bind and canaccessvalue(name) and bind.name == name then
		return bind
	end
end

---@param teleport SPFTeleport
local function Known(teleport)
	if teleport.item then
		return C_Item.GetItemCount(teleport.item) > 0
	end
	return C_SpellBook.IsSpellKnown(teleport.spell)
end

---@param teleport SPFTeleport
local function Stocked(teleport)
	for item, count in pairs(teleport.reagents or {}) do
		if C_Item.GetItemCount(item) < count then
			return false
		end
	end
	return true
end

-- Seconds of cooldown left and the GetTime() it ends at, or nil while the client keeps it secret.
---@param teleport SPFTeleport
---@return number?, number?
local function Cooldown(teleport)
	local start, duration
	if teleport.item then
		start, duration = C_Item.GetItemCooldown(teleport.item)
	else
		local info = C_Spell.GetSpellCooldown(teleport.spell)
		if info then
			start, duration = info.startTime, info.duration
		end
	end
	if not (canaccessvalue(start) and canaccessvalue(duration)) then
		return nil
	end
	if start and duration and start > 0 then
		local deadline = start + duration
		return math.max(0, deadline - GetTime()), deadline
	end
	return 0, 0
end

-- The cast time the client reports for the spell now, in ms; the shipped one when it reports none.
---@param teleport SPFTeleport
---@return number
local function CastTime(teleport)
	local info = C_Spell.GetSpellInfo(teleport.spell)
	local cast = info and info.castTime
	return canaccessvalue(cast) and cast and cast > 0 and cast or teleport.cast
end

-- What the client says about each teleport: whether this character has it, and when it can be cast (nil without its
-- reagents or while the cooldown is secret). A replan reads this every few seconds and the bags alone are many client
-- calls, so it is read once and kept until an event says the bags, the spellbook or a cooldown changed (Init below),
-- or until the earliest cooldown it holds ends.
---@class SPFTeleportState
---@field known boolean
---@field deadline number? the GetTime() its cooldown ends at, 0 when there is none
---@type table<SPFTeleport, SPFTeleportState>
local states = {}
local list, fresh, expires = nil, false, math.huge

---@return table<SPFTeleport, SPFTeleportState>
local function States()
	local now = GetTime()
	if fresh and list == ns.Teleports and now < expires then
		return states
	end
	if list ~= ns.Teleports then
		-- Another teleport list: the places built from the last one go with it.
		placesKey = nil
	end
	states, list, fresh, expires = {}, ns.Teleports, true, math.huge
	for _, teleport in ipairs(ns.Teleports or {}) do
		local known, deadline = Known(teleport), nil
		if known and Stocked(teleport) then
			deadline = select(2, Cooldown(teleport))
			if not deadline then
				-- A secret cooldown is never kept: the next read asks again.
				expires = now
			end
		end
		if deadline and deadline > now then
			expires = math.min(expires, deadline)
		end
		states[teleport] = { known = known, deadline = deadline }
	end
	return states
end

-- Seconds until the teleport can be cast, or nil when it cannot be.
---@param state SPFTeleportState
---@return number?
local function Wait(state)
	local deadline = state.deadline
	return deadline and math.max(0, deadline - GetTime())
end

-- The Hearthstone and the bind point it recalls to, when this character could use it: the item in the bags and a bind
-- point the client and the last binding or landing agree on. Neither switch hides it, since the map's innkeeper button
-- (UI/HearthPin.lua) is how the player flips the Hearthstone one.
---@param now? number server ms, for readyAt
---@return SPFHearthstone?
function ns.Hearthstone(now)
	local bind = Bind()
	if not bind then
		return nil
	end
	for _, teleport in ipairs(ns.Teleports or {}) do
		local state = teleport.item == HEARTHSTONE and States()[teleport]
		if state then
			if not state.known then
				return nil
			end
			local wait = Wait(state)
			return {
				name = bind.name,
				map = bind.map,
				x = bind.x,
				y = bind.y,
				place = {
					map = bind.map,
					x = bind.x,
					y = bind.y,
					z = bind.z,
					label = bind.name,
					bind = true,
					spell = teleport.spell,
					item = teleport.item,
					cast = CastTime(teleport),
				},
				readyAt = wait and (now or 0) + wait * 1000 or nil,
			}
		end
	end
end

-- The places keep their identity while the set is unchanged, so the planner keeps its topology; only readiness
-- ([index] = server ms when it can be cast) is read afresh.
---@param now number server ms
---@return SPFTeleportPlace[] places, table<number, number> ready, table<number, number> state
function ns.UsableTeleports(now)
	local hearth, class = HearthAllowed(), ClassTeleportsAllowed()
	if not (hearth or class) then
		return NONE, NONE, NONE
	end
	local bind, known, keys = Bind(), {}, {}
	local state, read = {}, States()
	for _, teleport in ipairs(ns.Teleports) do
		-- A teleport that lands at the bind point is the Hearthstone or Astral Recall; the rest have a place of
		-- their own and follow the class teleport switch.
		local wanted = teleport.bind and hearth or (teleport.to and class)
		if wanted and (teleport.to or (teleport.bind and bind)) and read[teleport].known then
			known[#known + 1] = teleport
			keys[#keys + 1] = teleport.spell
		end
	end
	local key = table.concat(keys, ",") .. (bind and string.format(":%d:%.17g:%.17g", bind.map, bind.x, bind.y) or "")
	if key ~= placesKey then
		placesKey, places, sources = key, {}, known
		for index, teleport in ipairs(known) do
			local to = teleport.to or bind --[[@as SPFPoint]]
			places[index] = {
				map = to.map,
				x = to.x,
				y = to.y,
				z = to.z,
				label = not teleport.to and bind and bind.name or nil,
				bind = teleport.bind,
				spell = teleport.spell,
				item = teleport.item,
				cast = CastTime(teleport),
			}
		end
	end
	local ready = {}
	for index, teleport in ipairs(sources) do
		local deadline = read[teleport].deadline
		if deadline then
			ready[index] = now + Wait(read[teleport]) * 1000
			state[index] = deadline > GetTime() and deadline or 0
		end
	end
	return places, ready, state
end

-- A bind teleport's landing: after the cast, the travel clock samples where you are, and the first jump faster than
-- any mount (or onto another map, or out of an instance with no position) is where it set you down. A loading
-- screen's end looks again; the wait ends a minute after the cast, or after the loading screen it ends in.
local JUMP_YARDS, JUMP_SPEED, WAIT, AFTER_LOADING = 100, 20, 60, 10
local bindSpells = {}
-- The events that change what States() read: the bags (items and reagents), the spellbook, and cooldowns.
local CHANGES =
	{ BAG_UPDATE_DELAYED = true, SPELLS_CHANGED = true, SPELL_UPDATE_COOLDOWN = true, BAG_UPDATE_COOLDOWN = true }
---@type {name: string, map?: number, x?: number, y?: number, at: number, deadline: number}?
local landing

local function Record(name, map, x, y)
	local bind = ns.charDB.bind
	-- The same inn, already known beside its innkeeper or from an earlier landing: kept, so its places stand.
	if bind and bind.name == name and bind.map == map and (bind.x - x) ^ 2 + (bind.y - y) ^ 2 <= JUMP_YARDS ^ 2 then
		return
	end
	ns.charDB.bind = { name = name, map = map, x = x, y = y }
	if ns.RefreshHearthPin then
		ns.RefreshHearthPin()
	end
end

local function Sample()
	local wait = landing
	if not wait then
		return
	end
	local now = GetTime()
	if now > wait.deadline then
		landing = nil
		return
	end
	local name = GetBindLocation()
	if not canaccessvalue(name) then
		return
	end
	if name ~= wait.name then
		landing = nil
		return
	end
	local x, y, _, map = ns.JourneyPosition()
	if not (x and y and map) then
		wait.map, wait.x, wait.y = nil, nil, nil
		return
	end
	local limit = JUMP_YARDS + JUMP_SPEED * (now - wait.at)
	if not wait.map or map ~= wait.map or (x - wait.x) ^ 2 + (y - wait.y) ^ 2 > limit ^ 2 then
		landing = nil
		Record(name, map, x, y)
		return
	end
	wait.map, wait.x, wait.y, wait.at = map, x, y, now
end

ns.Init(function()
	for _, teleport in ipairs(ns.Teleports) do
		if teleport.bind then
			bindSpells[teleport.spell] = true
		end
	end
	ns.OnTravelTick(Sample)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("HEARTHSTONE_BOUND")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	for event in pairs(CHANGES) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event, _, _, spell)
		if CHANGES[event] then
			fresh = false
			return
		end
		if event == "PLAYER_ENTERING_WORLD" then
			if landing then
				landing.deadline = GetTime() + AFTER_LOADING
				Sample()
			end
			return
		end
		if event == "UNIT_SPELLCAST_SUCCEEDED" and not (canaccessvalue(spell) and bindSpells[spell]) then
			return
		end
		local x, y, _, map = ns.JourneyPosition()
		local name = GetBindLocation()
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if canaccessvalue(name) and name then
				local now = GetTime()
				-- Inside an instance there is no position: the first one outside is the landing.
				landing = { name = name, map = map, x = x, y = y, at = now, deadline = now + WAIT }
				if not (x and y) then
					landing.map = nil
				end
				ns.WakeTravel()
			end
		elseif x and y and map and canaccessvalue(name) then
			landing = nil
			ns.charDB.bind = { name = name, map = map, x = x, y = y }
		else
			landing = nil
			ns.charDB.bind = nil
		end
		if ns.RefreshHearthPin then
			ns.RefreshHearthPin()
		end
	end)
end)
