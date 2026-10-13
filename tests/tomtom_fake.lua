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
function Fake.New(saved)
	local tomtom = { profile = { stickycorpse = false, setclosest = true } }
	local waypoints, valid, profile = {}, {}, {}
	local arrow
	tomtom.waypoints = waypoints

	local function Key(m, x, y, title)
		return string.format("%d:%s:%s:%s", m, tostring(x), tostring(y), tostring(title))
	end

	function tomtom:SetCrazyArrow(uid, _, _)
		if arrow and arrow.corpse and self.profile.stickycorpse then
			return
		end
		arrow = uid
	end

	function tomtom.ClearWaypoint(_, uid)
		valid[uid] = nil
	end

	function tomtom.IsValidWaypoint(_, uid)
		assert(type(uid) == "table", "TomTom:IsValidWaypoint(waypoint) UID is not a table.")
		local map = waypoints[uid[1]]
		return map ~= nil and map[Key(uid[1], uid[2], uid[3], uid.title)] == uid
	end

	function tomtom:AddWaypoint(m, x, y, opts)
		opts = opts or {}
		if opts.crazy == nil then
			opts.crazy = true
		end
		if opts.persistent == nil then
			opts.persistent = true
		end
		local key = Key(m, x, y, opts.title)
		if waypoints[m] and waypoints[m][key] then
			return waypoints[m][key]
		end
		local uid = { m, x, y, title = opts.title, from = opts.from or "?" }
		for k, v in pairs(opts) do
			if not uid[k] then
				uid[k] = v
			end
		end
		valid[uid] = true
		if opts.crazy then
			self:SetCrazyArrow(uid, 15, opts.title)
		end
		waypoints[m] = waypoints[m] or {}
		waypoints[m][key] = uid
		if opts.persistent then
			profile[key] = uid
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
		if arrow and not valid[arrow] then
			arrow = nil
			if self.profile.setclosest and closest and valid[closest] then
				self:SetCrazyArrow(closest, 15, closest.title)
			end
		end
	end

	-- The arrow's own menu: "Clear waypoint from crazy arrow" leaves the waypoint set.
	function tomtom:ClearCrazyArrowPoint(remove)
		if arrow then
			if remove then
				self:RemoveWaypoint(arrow)
			else
				arrow = nil
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
		local copy = { uid[1], uid[2], uid[3], title = uid.title, persistent = true }
		profile[Key(uid[1], uid[2], uid[3], uid.title)] = copy
	end
	return tomtom
end

return Fake
