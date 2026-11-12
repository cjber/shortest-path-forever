---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Bouncing arrows either side of the nameplate of the NPC a Nearby services journey walks to. The nameplate itself
-- is never changed: the arrows are this addon's own frame and textures, anchored to its health bar the way Adventure
-- Guide Forever marks its current step's NPC. NPE_ArrowRight points right on the left, NPE_ArrowLeft points left on
-- the right, so both point at the nameplate. The journey's arrival keeps them on the plate the player reached, until
-- that plate goes away, so they cannot vanish a step short of the NPC.
local ARROW_LEFT_ATLAS = "NPE_ArrowRight"
local ARROW_RIGHT_ATLAS = "NPE_ArrowLeft"
local ARROW_SIZE = 22
local ARROW_BOB = 3
local ARROW_GAP = 6

local function Readable(value)
	local canAccess = rawget(_G, "canaccessvalue")
	if canAccess and not canAccess(value) then
		return nil
	end
	return value
end

-- The decimal creature entry is the sixth field; the seventh field identifies the individual spawn.
---@param guid string?
---@return integer?
local function CreatureEntry(guid)
	local entry = type(guid) == "string" and guid:match("^Creature%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-%x+$")
	return tonumber(entry)
end

---@class SPFNpcArrowsModule
local NpcArrows = {}
ns.NpcArrows = NpcArrows

---@class SPFNpcArrowsTarget
---@field npc integer
---@field label string?
---@field arrived? boolean

---@type table<string, true>
local plates = {}
---@type SPFNpcArrowsFrame?
local arrowFrame
---@type Region?
local arrowBar
---@type string?
local arrowUnit
---@type SPFNpcArrowsTarget?
local target
-- The plate the arrows were on at arrival, whose removal ends them.
---@type string?
local arrivedUnit
local bounce = 0
local bobbing = false

local function Enabled()
	return ns.db ~= nil and ns.db.npcArrows == true
end

-- Whether `unit` is the target's NPC: by the creature entry in its GUID, or, when the GUID cannot be read, by the
-- target's title against the unit's exact name.
---@param stop SPFNpcArrowsTarget
---@param unit string
---@return boolean
function NpcArrows.Matches(stop, unit)
	if not stop.npc then
		return false
	end
	local guid = Readable(UnitGUID(unit))
	if guid then
		local entry = CreatureEntry(guid)
		return entry ~= nil and entry == stop.npc
	end
	local name = Readable(UnitName(unit))
	return type(stop.label) == "string" and stop.label ~= "" and name == stop.label
end

local function Hide()
	if arrowFrame then
		arrowFrame:SetScript("OnUpdate", nil)
		arrowFrame:Hide()
	end
	bobbing = false
	arrowBar = nil
	arrowUnit = nil
end

-- Both arrows bob toward the nameplate and back together: the left one moves right and the right one left as
-- `shift` grows.
---@param shift number
local function Place(shift)
	if not (arrowFrame and arrowFrame.Left and arrowFrame.Right and arrowBar) then
		return
	end
	arrowFrame.Left:ClearAllPoints()
	arrowFrame.Left:SetPoint("RIGHT", arrowBar, "LEFT", -ARROW_GAP + shift, 0)
	arrowFrame.Right:ClearAllPoints()
	arrowFrame.Right:SetPoint("LEFT", arrowBar, "RIGHT", ARROW_GAP - shift, 0)
end

local function Bob(_, elapsed)
	bounce = (bounce + elapsed) % 1
	Place(math.sin(bounce * math.pi * 2) * ARROW_BOB)
end

---@return SPFNpcArrowsFrame
local function EnsureArrow()
	if not arrowFrame then
		local frame = CreateFrame("Frame", "ShortestPathForeverNpcArrows", UIParent) --[[@as SPFNpcArrowsFrame]]
		frame:SetSize(ARROW_SIZE, ARROW_SIZE)
		frame:Hide()
		frame.Left = frame:CreateTexture(nil, "ARTWORK")
		ns.Art.Fit(frame.Left, ARROW_LEFT_ATLAS, ARROW_SIZE, ARROW_SIZE)
		frame.Right = frame:CreateTexture(nil, "ARTWORK")
		ns.Art.Fit(frame.Right, ARROW_RIGHT_ATLAS, ARROW_SIZE, ARROW_SIZE)
		arrowFrame = frame
	end
	return arrowFrame
end

-- The nameplate unit the target's NPC is on: the arrows' current one while it still matches, else the first matching
-- plate on screen.
---@param stop SPFNpcArrowsTarget
---@return string?
local function FindUnit(stop)
	local unit = arrowUnit
	if unit and plates[unit] and NpcArrows.Matches(stop, unit) then
		return unit
	end
	for candidate in pairs(plates) do
		if NpcArrows.Matches(stop, candidate) then
			return candidate
		end
	end
end

---@return string?
function NpcArrows.ArrowUnit()
	return arrowUnit
end

function NpcArrows.Refresh()
	if not (Enabled() and target) then
		Hide()
		return
	end
	local unit
	if target.arrived then
		unit = arrivedUnit
		if not (unit and plates[unit] and NpcArrows.Matches(target, unit)) then
			unit = nil
		end
	else
		unit = FindUnit(target)
	end
	if not unit then
		Hide()
		return
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not (plate and plate:IsShown()) then
		Hide()
		return
	end
	local frame = EnsureArrow()
	arrowUnit = unit
	local unitFrame = plate.UnitFrame
	arrowBar = (unitFrame and unitFrame.healthBar) or plate
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", arrowBar, "CENTER")
	Place(0)
	if not bobbing then
		bobbing = true
		frame:SetScript("OnUpdate", Bob)
	end
	frame:Show()
end

-- The setting's callback, and the journey's own changes: show or hide without a reload. A stop with an npc is the
-- nameplate to mark; the journey's arrival keeps it until the player walks away, and the player's clear ends it.
---@param point SPFPoint?
---@param reason? "arrived"|"cleared"
local function JourneyChanged(point, reason)
	if point and point.npc then
		target, arrivedUnit = { npc = point.npc, label = point.label }, nil
	elseif point then
		target, arrivedUnit = nil, nil
	elseif reason ~= "arrived" or not target then
		target, arrivedUnit = nil, nil
	else
		arrivedUnit = FindUnit(target)
		if arrivedUnit then
			target.arrived = true
		else
			target = nil
		end
	end
	NpcArrows.Refresh()
end

function ns.RefreshNpcArrows()
	NpcArrows.Refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		plates[unit] = true
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		plates[unit] = nil
		if target and target.arrived and unit == arrivedUnit then
			target, arrivedUnit = nil, nil
		end
	end
	NpcArrows.Refresh()
end)

ns.Init(function()
	-- After every file has loaded, so API.lua's ns.JourneyChanged exists to hook.
	hooksecurefunc(ns, "JourneyChanged", JourneyChanged) -- taint-ok: ns is this addon's own namespace table.
end)
