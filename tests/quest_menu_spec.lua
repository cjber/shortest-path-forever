-- Under the gamepad interface the game's own menus are left to the game (UI/MenuModifier.lua, #645). The quest list's
-- *More options* action on Y opens MENU_QUEST_MAP_LOG_TITLE, and a right-click in the objective tracker opens
-- MENU_QUEST_OBJECTIVE_TRACKER. Forever's FrameControlsManager takes each menu into its focus in the same call, and a
-- menu an addon added to is tainted, so the focus's protected SetPreferredGamepadInteractTarget is refused and the
-- action does nothing (#788). Every entry this addon adds goes through ns.ModifyMenu, which withdraws them while the
-- gamepad interface is on and puts them back when it is off.
local gamepad = false
local registered, frames = {}, {}
local function Handle(tag, callback)
	local handle = { tag = tag, callback = callback }
	function handle:Unregister()
		if registered[tag] == self then
			registered[tag] = nil
		end
	end
	registered[tag] = handle
	return handle
end
local function Frame()
	local frame = {}
	function frame:RegisterEvent(event)
		self.event = event
		frames[#frames + 1] = self
	end
	frame.UnregisterEvent = function() end
	function frame:SetScript(name, fn)
		self[name] = fn
	end
	frame.SetSize = function() end
	frame.Hide = function() end
	return frame
end
local ns = {
	db = { journey = true },
	L = setmetatable({}, {
		__index = function(_, phrase)
			return phrase
		end,
	}),
	TaxiNodes = {},
	StartJourney = function() end,
	Locate = function() end,
	Init = function(fn)
		fn()
	end,
	GamepadUI = function()
		return gamepad
	end,
	core = {
		SafeCall = function(_, fn, ...)
			return fn(...)
		end,
	},
	NewMenuDescription = function(kind, text)
		return { kind = kind, text = text }
	end,
	FamilyHints = { AddQuestMenu = function() end },
	Canvas = { OnClick = function() end },
}
local env = setmetatable({
	CreateFrame = Frame,
	Menu = { ModifyMenu = Handle },
	IsAltKeyDown = function()
		return false
	end,
	IsShiftKeyDown = function()
		return false
	end,
	ChatEdit_GetActiveWindow = function() end,
	GetMouseFoci = function()
		return {}
	end,
	Minimap = { HookScript = function() end },
	WorldMapFrame = {
		IsShown = function()
			return false
		end,
		ScrollContainer = { IsMouseOver = function() end },
		GetMapID = function()
			return 1440
		end,
		GetNormalizedCursorPosition = function()
			return 0.5, 0.5
		end,
		AddCanvasClickHandler = function() end,
		AddGlobalPinMouseActionHandler = function() end,
	},
	MapCanvasMixin = { MouseAction = { Click = 3 } },
	C_Map = {},
	Enum = { UIMapType = { Continent = 2 } },
	CreateVector2D = function(x, y)
		return { x = x, y = y }
	end,
}, { __index = _G })
for _, file in ipairs({ "UI/MenuModifier.lua", "Journey/JourneyInput.lua" }) do
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end
assert(ns.ModifyMenu, "the shared menu entries module is loaded before the quest menus")

-- The entry a menu the client builds carries, from the modifier the client would run for it.
local function Build(tag, owner)
	local handle = assert(registered[tag], "the game's " .. tag .. " menu carries our entry")
	local built = {}
	handle.callback(owner, {
		CreateTitle = function() end,
		CreateDivider = function() end,
		CreateButton = function(_, text)
			built[#built + 1] = text
		end,
	})
	return built
end
assert(Build("MENU_QUEST_MAP_LOG_TITLE", { questID = 4242 })[1] == "Plan journey", "the quest list's menu has it")
Build("MENU_QUEST_OBJECTIVE_TRACKER", { id = 4242 })

-- One gamepad transition, as the client fires it: the shared module takes our entries back out, so the game builds
-- its menu with none of our fields in it and its own Y action runs.
local transition
for _, frame in ipairs(frames) do
	if frame.event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
		transition = frame
	end
end
assert(transition and transition.OnEvent, "the shared module follows the interface in use")
gamepad = true
transition.OnEvent(transition)
assert(registered.MENU_QUEST_MAP_LOG_TITLE == nil, "under the gamepad the quest list's menu is the game's own (#788)")
assert(registered.MENU_QUEST_OBJECTIVE_TRACKER == nil, "under the gamepad the tracker's menu is the game's own (#788)")
gamepad = false
transition.OnEvent(transition)
assert(registered.MENU_QUEST_MAP_LOG_TITLE, "leaving the gamepad puts Plan journey back in the quest list's menu")
assert(registered.MENU_QUEST_OBJECTIVE_TRACKER, "and back in the tracker's menu")
assert(Build("MENU_QUEST_MAP_LOG_TITLE", { questId = 4242 })[1] == "Plan journey", "the entry works again")
print("quest menus: the gamepad interface leaves the game's quest menus to the game: ok")
