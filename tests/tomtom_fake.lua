-- A stand-in for TomTom v4.3.12-release (CurseForge file 9082779, Interface 16001 among others), written from its
-- source and kept to the behaviour Core/TomTom.lua relies on. File:line references are to that release.
--
-- * The addon table is the global TomTom from the moment its files load (AddonCore.lua:16-19), before its own
--   ADDON_LOADED; its methods are called through the table (`self:`/`TomTom:`/`addon:`), so a hook on it sees them.
-- * PLAYER_LOGIN runs Enable (AddonCore.lua:251-265, 308), whose first act is ReloadWaypoints (TomTom.lua:219-220):
--   ClearAllWaypoints, which calls ClearWaypoint on each (TomTom.lua:317-324), then AddWaypoint for every saved
--   waypoint, silent (TomTom.lua:342-384). PLAYER_ENTERING_WORLD comes after.
-- * AddWaypoint(m, x, y, opts) (TomTom.lua:971-1028): defaults crazy to the autoqueue setting, on by default
--   (TomTom.lua:76); returns the existing waypoint for the same map, x, y and title without touching the arrow
--   (TomTom.lua:988-991); else builds {m, x, y, title = opts.title, from = opts.from or "?"} plus every option
--   (TomTom.lua:994-1001), calls SetCrazyArrow(uid, arrivaldistance, title) when crazy (TomTom.lua:1005-1008) and
--   records it.
-- * SetCrazyArrow(uid, dist, title) (TomTom_CrazyArrow.lua:83-100) points the arrow, unless it is on the corpse and
--   the sticky-corpse option is set.
-- * RemoveWaypoint(uid) (TomTom.lua:874-892) errors on a non-table, calls ClearWaypoint, then forgets it.
--   "Remove all waypoints" and /way reset all reset the profile and call ReloadWaypoints (TomTom.lua:672-678), so
--   they clear through ClearWaypoint alone.
-- * The arrow notices a waypoint that is gone on its next update and, with setclosest (on by default,
--   TomTom.lua:84), takes the closest one left through SetCrazyArrow (TomTom_CrazyArrow.lua:114-131, 1345-1371).
-- * Dying adds a waypoint {title = "My Corpse", persistent = false, corpse = true}, crazy by default
--   (TomTom_Corpse.lua:60-68); coming back to life removes it with RemoveWaypoint (TomTom_Corpse.lua:24-29, 98-113).
-- * /way adds a waypoint titled with the rest of the line, or "TomTom waypoint", from "TomTom/way"
--   (TomTom.lua:1599-1667).
local Fake = {}

---@param saved? table[] the waypoints TomTom saved last session: {map, x, y, title = ...}
---@param wayframe? table the arrow frame, when a spec observes its visibility
---@param modern? boolean use TomTom 4.4.1 waypoint storage and arrow removal order
function Fake.New(saved, wayframe, modern)
	local tomtom = { profile = { stickycorpse = false, setclosest = true, savewaypoints = true } }
	local waypoints, valid, profile = {}, {}, {}
	local arrow, closestPending
	local hijacked = false
	tomtom.waypoints = waypoints

	local function Key(m, x, y, title)
		return string.format("%d:%s:%s:%s", m, tostring(x), tostring(y), tostring(title))
	end

	function tomtom:SetCrazyArrow(uid, _, _)
		if arrow and arrow.corpse and self.profile.stickycorpse then
			return
		end
		arrow, closestPending = uid, false
		if wayframe then
			wayframe:Show()
		end
	end

	function tomtom.HijackCrazyArrow(_, _)
		hijacked = true
		if wayframe then
			wayframe:Show()
		end
	end

	function tomtom.ReleaseCrazyArrow()
		hijacked = false
	end

	function tomtom.CrazyArrowIsHijacked()
		return hijacked
	end

	function tomtom.IsCrazyArrowEmpty()
		return arrow == nil
	end

	function tomtom.ClearWaypoint(_, uid)
		valid[uid] = nil
		if modern and arrow == uid then
			arrow, closestPending = nil, true
		end
	end

	function tomtom.IsValidWaypoint(_, uid)
		assert(type(uid) == "table", "TomTom:IsValidWaypoint(waypoint) UID is not a table.")
		local map = waypoints[uid[1]]
		local stored = map and map[Key(uid[1], uid[2], uid[3], uid.title)]
		return stored ~= nil and (modern or stored == uid)
	end

	function tomtom:AddWaypoint(m, x, y, opts)
		opts = opts or {}
		if opts.crazy == nil then
			opts.crazy = true
		end
		if opts.persistent == nil then
			opts.persistent = self.profile.savewaypoints
		end
		local key = Key(m, x, y, opts.title)
		if waypoints[m] and waypoints[m][key] then
			return waypoints[m][key]
		end
		local uid = { m, x, y, title = opts.title, from = opts.from or (modern and opts.source) or "?" }
		for k, v in pairs(opts) do
			if not uid[k] then
				uid[k] = v
			end
		end
		valid[uid] = true
		if opts.crazy and not modern then
			self:SetCrazyArrow(uid, 15, opts.title)
		end
		waypoints[m] = waypoints[m] or {}
		waypoints[m][key] = uid
		if opts.persistent then
			profile[key] = uid
		end
		if opts.crazy and modern then
			self:SetCrazyArrow(uid, 15, opts.title)
		end
		return uid
	end

	function tomtom:RemoveWaypoint(uid)
		if not uid then
			return
		end
		assert(type(uid) == "table", "TomTom:RemoveWaypoint(uid) UID is not a table.")
		self:ClearWaypoint(uid)
		local key = Key(uid[1], uid[2], uid[3], uid.title)
		profile[key] = nil
		if waypoints[uid[1]] then
			waypoints[uid[1]][key] = nil
		end
	end

	function tomtom:ClearAllWaypoints()
		for _, entries in pairs(waypoints) do
			for _, uid in pairs(entries) do
				self:ClearWaypoint(uid)
			end
		end
	end

	function tomtom:ReloadWaypoints()
		self:ClearAllWaypoints()
		for map in pairs(waypoints) do
			waypoints[map] = nil
		end
		local keys = {}
		for key in pairs(profile) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			local uid = profile[key]
			local options = { silent = true, from = "Anon" }
			for k, v in pairs(uid) do
				if type(k) == "string" and k ~= "callbacks" then
					options[k] = v
				end
			end
			profile[key] = nil
			self:AddWaypoint(uid[1], uid[2], uid[3], options)
		end
	end

	-- PLAYER_LOGIN: TomTom's Enable.
	function tomtom:Enable()
		self:ReloadWaypoints()
	end

	-- The popup's OnAccept, behind "Remove all waypoints" and /way reset all.
	function tomtom:RemoveAll()
		for key in pairs(profile) do
			profile[key] = nil
		end
		self:ReloadWaypoints()
	end

	-- The arrow's next update: a waypoint that is gone is dropped, and the closest one left is taken.
	---@param closest? table the waypoint GetClosestWaypoint would find, if any
	function tomtom:ArrowUpdate(closest)
		if wayframe and (wayframe.hidden or hijacked) then
			return
		end
		if closestPending or (arrow and not valid[arrow]) then
			arrow, closestPending = nil, false
			if self.profile.setclosest and closest and valid[closest] then
				self:SetCrazyArrow(closest, 15, closest.title)
			end
		end
		if not arrow and wayframe then
			wayframe:Hide()
		end
	end

	-- The arrow's own menu: "Clear waypoint from crazy arrow" leaves the waypoint set.
	function tomtom:ClearCrazyArrowPoint(remove)
		if arrow then
			if remove then
				self:RemoveWaypoint(arrow)
			else
				local prior = arrow
				arrow = nil
				-- Specs supply the nearest remaining point instead of querying the player's position.
				local closest = self.closest
				if self.profile.setclosest and closest and closest ~= prior and self:IsValidWaypoint(closest) then
					self:SetCrazyArrow(closest, 15, closest.title)
				end
			end
		end
	end

	-- /way x y [title] on the given map.
	function tomtom:Way(m, x, y, title)
		return self:AddWaypoint(m, x / 100, y / 100, { title = title or "TomTom waypoint", from = "TomTom/way" })
	end

	-- The corpse arrow, once the client reports where the body lies, and its removal when you live again.
	function tomtom:Die(m, x, y)
		self.corpseUid = self:AddWaypoint(m, x, y, { title = "My Corpse", persistent = false, corpse = true })
		return self.corpseUid
	end

	function tomtom:Revive()
		if self.corpseUid then
			self:RemoveWaypoint(self.corpseUid)
			self.corpseUid = nil
		end
	end

	function tomtom.Arrow()
		return arrow
	end

	for _, uid in ipairs(saved or {}) do
		local copy = { uid[1], uid[2], uid[3], persistent = true }
		for key, value in pairs(uid) do
			copy[key] = value
		end
		profile[Key(uid[1], uid[2], uid[3], uid.title)] = copy
	end
	return tomtom
end

-- RestedXP-TomTom 1.5.2 takes ownership by waypoint identity. The quiet delay is a fixture value.
function Fake.Bridge(env)
	local quietDelay = 1
	local bridge = { paused = false }
	local waypoint, lastElement, hooked, quietSince, emptySince
	local function HasForeign(tomtom)
		if type(tomtom.waypoints) ~= "table" then
			return true
		end
		for _, entries in pairs(tomtom.waypoints) do
			for _, uid in pairs(entries) do
				if uid ~= waypoint then
					return true
				end
			end
		end
		return false
	end

	local function Remove(tomtom)
		if waypoint and tomtom:IsValidWaypoint(waypoint) then
			tomtom:RemoveWaypoint(waypoint)
		end
		waypoint, lastElement = nil, nil
	end

	local function Tick(force)
		local tomtom, arrow = env.TomTom, env.RXPG_ARROW
		if not (tomtom and arrow) then
			return
		end
		arrow:SetAlpha(0)
		arrow:Show()
		if not hooked then
			hooked = true
			bridge.paused = HasForeign(tomtom)
			env.hooksecurefunc(tomtom, "SetCrazyArrow", function(_, uid)
				if uid ~= waypoint then
					bridge.paused, quietSince = true, nil
				end
			end)
		end
		local now = env.GetTime()
		local reselect = force
		if force then
			bridge.paused, quietSince = false, nil
		elseif bridge.paused then
			if HasForeign(tomtom) then
				quietSince = nil
			else
				quietSince = quietSince or now
				if now - quietSince >= quietDelay then
					bridge.paused, quietSince, reselect = false, nil, true
				end
			end
		end
		local element = arrow.element
		if not element then
			emptySince = emptySince or now
			if now - emptySince >= quietDelay then
				Remove(tomtom)
			end
			return
		end
		emptySince = nil
		if element ~= lastElement or not (waypoint and tomtom:IsValidWaypoint(waypoint)) then
			Remove(tomtom)
			lastElement = element
			waypoint = tomtom:AddWaypoint(element.zone, element.x / 100, element.y / 100, {
				title = element.title,
				source = "RXPGuides",
				persistent = false,
				crazy = false,
			})
			reselect = true
		end
		if reselect and not bridge.paused then
			tomtom:SetCrazyArrow(waypoint, 15, waypoint.title)
		end
	end

	local frame = env.CreateFrame("Frame")
	local ticksOn = { PLAYER_ENTERING_WORLD = true, PLAYER_CONTROL_GAINED = true, PLAYER_ALIVE = true }
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			local elapsed = 0
			frame:SetScript("OnUpdate", function(_, delta)
				elapsed = elapsed + delta
				if elapsed >= 0.25 then
					elapsed = elapsed % 0.25
					Tick()
				end
			end)
			env.C_Timer.NewTicker(0.5, function(ticker)
				Tick()
				if env.RXPG_ARROW and env.RXPG_ARROW.element then
					ticker:Cancel()
				end
			end, 10)
			env.hooksecurefunc(env.RXP, "DrawArrow", function()
				Tick()
			end)
		elseif ticksOn[event] then
			Tick()
		end
	end)
	env.RXPTOMTOM_SetCurrentWaypoint = function()
		Tick(true)
	end
	function bridge.Waypoint()
		return waypoint
	end
	return bridge
end

return Fake
