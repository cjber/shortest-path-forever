-- The two bouncing arrows beside the nameplate of the NPC a Nearby services journey walks to (UI/NpcArrows.lua):
-- matching by the GUID's creature entry with the stop's title as the unreadable-GUID fallback, the target the journey
-- sets and keeps on arrival until that plate goes away, the setting, the bob's own OnUpdate, and that the nameplate is
-- never written to.
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end

-- A client frame: what it was told and what it was asked.
local function widget(kind, name, parent)
	local frame = { kind = kind, name = name, parent = parent, scripts = {}, events = {}, shown = true }
	local methods = {}
	function methods:SetScript(script, callback)
		self.scripts[script] = callback
	end
	function methods:Show()
		self.shown = true
	end
	function methods:Hide()
		self.shown = false
	end
	function methods:IsShown()
		return self.shown
	end
	function methods:SetSize(width, height)
		self.width, self.height = width, height
	end
	function methods:CreateTexture()
		local texture = widget("Texture", nil, self)
		texture.SetAtlas = function(region, atlas)
			region.atlas = atlas
		end
		return texture
	end
	function methods:ClearAllPoints()
		self.point = nil
	end
	function methods:SetPoint(...)
		self.point = { ... }
	end
	function methods:RegisterEvent(event)
		self.events[event] = true
	end
	setmetatable(frame, { __index = methods })
	return frame
end

-- A nameplate or health bar that records every call and write, so the spec can prove the addon only anchors to it.
local function guarded()
	local calls = {}
	local function record(key)
		calls[#calls + 1] = key
	end
	return calls,
		setmetatable({}, {
			__index = function(_, key)
				return function()
					record(key)
				end
			end,
			__newindex = function(target, key, value)
				record(key)
				rawset(target, key, value)
			end,
		})
end

local nameplateCalls, healthBar = guarded()
local writes = {}
local plate
do
	local frame = { UnitFrame = { healthBar = healthBar } }
	plate = setmetatable(frame, {
		__index = function(_, key)
			if key == "IsShown" then
				return function()
					return true
				end
			end
			return function()
				writes[#writes + 1] = key
			end
		end,
		__newindex = function(target, key, value)
			writes[#writes + 1] = key
			rawset(target, key, value)
		end,
	})
end

local frames = {}
local function CreateFrame(kind, name, parent)
	local frame = widget(kind, name, parent)
	frames[#frames + 1] = frame
	return frame
end

local secret = {}
local guid, unitName, plateFor = {}, {}, {}
local stop

local ns = {
	db = { npcArrows = true },
	JourneyChanged = function() end,
	Init = function(fn)
		fn()
	end,
}

local env = setmetatable({
	UIParent = {},
	CreateFrame = CreateFrame,
	C_NamePlate = {
		GetNamePlateForUnit = function(unit)
			return plateFor[unit]
		end,
	},
	UnitGUID = function(unit)
		return guid[unit]
	end,
	UnitName = function(unit)
		return unitName[unit]
	end,
	canaccessvalue = function(value)
		return value ~= secret
	end,
	hooksecurefunc = function(target, key, hook)
		local original = target[key]
		target[key] = function(...)
			original(...)
			hook(...)
		end
	end,
}, { __index = _G })
env._G = env
ns.Art = {
	Fit = function(texture, atlas, width, height)
		texture.atlas = atlas
		texture.width, texture.height = width, height
		return true
	end,
}

setfenv(assert(loadfile("UI/NpcArrows.lua")), env)("ShortestPathForever", ns)
local NpcArrows = ns.NpcArrows

local function fire(event, unit)
	for _, frame in ipairs(frames) do
		if frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event, unit)
			return
		end
	end
	error("no event frame registered " .. event)
end

local function arrow()
	for _, frame in ipairs(frames) do
		if frame.name == "ShortestPathForeverNpcArrows" then
			return frame
		end
	end
end

---@param npcID integer
local function creature(npcID)
	return "Creature-0-6864-0-6-" .. npcID .. "-930B57223C"
end

-- Observed on the live Forever client: a readable GUID matches by entry, independently of the displayed name.
guid.live, unitName.live = "Creature-0-6864-0-6-859-930B57223C", "Different title"
check(NpcArrows.Matches({ npc = 859, label = "Guard Berton" }, "live"), "the observed live GUID yields entry 859")
check(
	not NpcArrows.Matches({ npc = 858, label = "Different title" }, "live"),
	"a readable GUID cannot fall back to a matching title"
)

-- A journey to one NPC, with its plate and another NPC's plate on screen: only the matching plate is marked.
guid.npc, unitName.npc = creature(123), "Innkeeper"
guid.other, unitName.other = creature(456), "Stable master"
plateFor.npc, plateFor.other = plate, plate
stop = { npc = 123, label = "Innkeeper" }
ns.JourneyChanged(stop)
fire("NAME_PLATE_UNIT_ADDED", "other")
check(arrow() == nil, "another NPC's plate gets no arrows")
fire("NAME_PLATE_UNIT_ADDED", "npc")
local frame = arrow()
check(frame ~= nil and frame.shown, "the stop's NPC plate gets the arrows")
equal(NpcArrows.ArrowUnit(), "npc", "the matching plate unit")
equal(frame.Left.atlas, "NPE_ArrowRight", "the left arrow points in")
equal(frame.Right.atlas, "NPE_ArrowLeft", "the right arrow points in")
equal(frame.Left.width, 22, "the left arrow is 22 wide")
equal(frame.Right.height, 22, "the right arrow is 22 high")
check(frame.point[1] == "CENTER" and frame.point[2] == healthBar, "the arrows anchor to the health bar")
check(frame.Left.point[2] == healthBar and frame.Right.point[2] == healthBar, "and each arrow to the same bar")
equal(frame.Left.point[4], -6, "the left arrow keeps its gap")
equal(frame.Right.point[4], 6, "the right arrow keeps its gap")
check(frame.scripts.OnUpdate ~= nil, "the bob runs while the arrows show")

-- Another plate of the same or another NPC does not steal the arrows from the matching one.
fire("NAME_PLATE_UNIT_ADDED", "other")
equal(NpcArrows.ArrowUnit(), "npc", "the matching plate keeps the arrows")

-- A GUID the client will not read falls back to the target's exact title.
guid.fallback, unitName.fallback = secret, "Innkeeper"
plateFor.fallback = plate
fire("NAME_PLATE_UNIT_REMOVED", "npc")
fire("NAME_PLATE_UNIT_REMOVED", "other")
check(arrow().shown == false and arrow().scripts.OnUpdate == nil, "a removed plate takes the arrows and the bob")
fire("NAME_PLATE_UNIT_ADDED", "fallback")
check(arrow().shown, "an unreadable GUID falls back to the exact name")
unitName.fallback = "Innkeeper's assistant"
NpcArrows.Refresh()
check(not arrow().shown and arrow().scripts.OnUpdate == nil, "a different exact name does not match")
unitName.fallback = "Innkeeper"
NpcArrows.Refresh()
check(arrow().shown, "the fallback matches again")

-- Arrival keeps the arrows on the plate the player reached, and that plate going away ends them.
ns.JourneyChanged(nil, "arrived")
check(arrow().shown and arrow().scripts.OnUpdate ~= nil, "arrival keeps the arrows on the matched plate")
equal(NpcArrows.ArrowUnit(), "fallback", "and on the same plate")
fire("NAME_PLATE_UNIT_REMOVED", "fallback")
check(not arrow().shown and arrow().scripts.OnUpdate == nil, "that plate going away ends the arrived arrows")
fire("NAME_PLATE_UNIT_ADDED", "fallback")
check(not arrow().shown, "a later plate for the same NPC gets none")

-- Arrival where no plate of the NPC is up clears the target at once.
fire("NAME_PLATE_UNIT_REMOVED", "fallback")
ns.JourneyChanged(stop)
check(not arrow().shown, "a journey whose NPC has no plate shows nothing")
ns.JourneyChanged(nil, "arrived")
fire("NAME_PLATE_UNIT_ADDED", "fallback")
check(not arrow().shown, "arrival with no matched plate clears at once")

-- The player clearing a journey hides them at once.
ns.JourneyChanged(stop)
check(arrow().shown, "a new journey to the NPC shows the arrows again")
ns.JourneyChanged(nil, "cleared")
check(not arrow().shown and arrow().scripts.OnUpdate == nil, "a cleared journey hides the arrows and stops the bob")

-- A new journey to another NPC moves the arrows to that NPC's plate.
ns.JourneyChanged(stop)
check(NpcArrows.ArrowUnit() == "fallback", "the matching plate gets the arrows again")
ns.JourneyChanged({ npc = 456, label = "Stable master" })
check(not arrow().shown, "the other NPC's plate is not up")
fire("NAME_PLATE_UNIT_ADDED", "other")
check(arrow().shown and NpcArrows.ArrowUnit() == "other", "a journey to another NPC moves the arrows to its plate")
ns.JourneyChanged({ map = 1, x = 0.5, y = 0.5 })
check(not arrow().shown and arrow().scripts.OnUpdate == nil, "a stop without an npc clears them")

-- The setting turns them off without a reload, and back on for the target the journey has.
ns.JourneyChanged(stop)
ns.db.npcArrows = true
ns.RefreshNpcArrows()
check(arrow().shown, "the setting on shows them")
ns.db.npcArrows = false
ns.RefreshNpcArrows()
check(not arrow().shown and arrow().scripts.OnUpdate == nil, "the setting off hides them")
ns.db.npcArrows = true
ns.RefreshNpcArrows()
check(arrow().shown and arrow().scripts.OnUpdate ~= nil, "turning it back on restores them and the bob")

-- The nameplate and its health bar were read through a method and anchored to, never written to.
equal(#writes, 0, "no call or write reaches the nameplate")
equal(#nameplateCalls, 0, "no call or write reaches its health bar")

print("npc arrows: " .. checks .. " checks: ok")
