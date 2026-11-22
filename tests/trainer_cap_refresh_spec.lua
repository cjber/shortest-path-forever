local ForeverCore = dofile("tests/forever_core.lua")
local destination
local unitLevel, frames, trainerNpc, trainerCap = 5, {}, 0, 0
local env = setmetatable({
	UnitClass = function()
		return "Paladin", "PALADIN", 2
	end,
	UnitLevel = function()
		return unitLevel
	end,
	CreateFrame = function()
		local frame = { events = {} }
		function frame:RegisterEvent(event)
			self.events[event] = true
		end
		function frame:SetScript(_, fn)
			self.handler = fn
		end
		frames[#frames + 1] = frame
		return frame
	end,
	UnitGUID = function()
		return "Creature-0-1-0-1-" .. trainerNpc .. "-0000000001"
	end,
	GetTrainerServiceTypeFilter = function()
		return true
	end,
	GetNumTrainerServices = function()
		return 1
	end,
	GetTrainerServiceInfo = function()
		return "Spell", "", "available", true
	end,
	GetTrainerServiceLevelReq = function()
		return trainerCap
	end,
	C_Map = {
		GetBestMapForUnit = function()
			return 1
		end,
		GetPlayerMapPosition = function()
			return {
				GetXY = function()
					return 0.1, 0.1
				end,
			}
		end,
	},
	C_Timer = {
		After = function(_, fn)
			fn()
		end,
	},
	InCombatLockdown = function()
		return false
	end,
	debugprofilestop = function()
		return 0
	end,
	geterrorhandler = function()
		return error
	end,
	MenuResponse = { CloseAll = 4 },
	SlashCmdList = {},
	ShortestPathForever = {
		API = {
			NavigateRoute = function(_, stops)
				destination = stops[1].npc
				return true
			end,
		},
	},
}, { __index = _G })
env._G = env
local core = ForeverCore.load(env, "ForeverCore", { "Core/Text.lua" })
env.ForeverCore = { Text = core.Text }

local starter, city, unknown = 925, 928, 244808
env.TweaksForever = {
	API = {
		version = 2,
		Trainers = function()
			return {}
		end,
	},
}
local ns = {
	db = {},
	ClassTrainers = { [starter] = 2, [city] = 2, [unknown] = 2 },
	ClassTrainerCaps = { [starter] = 8, [city] = 60, [unknown] = 60 },
	Init = function(fn)
		fn()
	end,
	ModifyMenu = function() end,
	WorldPoint = function(map, x, y)
		return { map = map, x = x, y = y }
	end,
	core = {
		SafeCall = function(_, fn, ...)
			fn(...)
			return true
		end,
	},
	NearbyQuestie = {
		Read = function(_, answer)
			answer({
				items = {},
				flags = {},
				npcs = {
					[starter] = { name = "Brother Sammuel", flags = 0, spawns = { { 1, 0.2, 0.1 } } },
					[city] = { name = "Lord Grayson Shadowbreaker", flags = 0, spawns = { { 1, 0.3, 0.1 } } },
					[unknown] = { name = "Aramis Hammerhand", flags = 0, spawns = { { 1, 0.4, 0.1 } } },
				},
			}, "ready")
		end,
	},
}
for _, file in ipairs({
	"Locales/enUS.lua",
	"UI/NearbyGroups.lua",
	"UI/NearbyEntrances.lua",
	"UI/NearbyRoles.lua",
	"UI/NearbyProfessions.lua",
	"UI/NearbyRank.lua",
	"UI/Nearby.lua",
}) do
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end

local function Fire(event, ...)
	for _, frame in ipairs(frames) do
		if frame.events[event] then
			frame.handler(frame, event, ...)
		end
	end
end

ns.NearbyServices.Request()
assert(ns.NearbyServices.State() == "ready", "the Nearby catalogue was built")
env.SlashCmdList.SPFNEAR("class")
assert(destination == starter, "a level 5 paladin goes to the nearest trainer, the starting-area one")

-- The client can still report the old level during PLAYER_LEVEL_UP.
Fire("PLAYER_LEVEL_UP", 9)
unitLevel = 9
local world = ns.NearbyServices.PlayerWorld()
assert(
	ns.NearbyServices.Sections(world)[1].rows[1].npc.id == city,
	"after levelling past the starting trainer's cap, the built class group skips that trainer"
)
env.SlashCmdList.SPFNEAR("class")
assert(destination == city, "and the class trainer journey goes to the city trainer")

-- Opening the city trainer teaches its real cap, below the player's level: the next one is offered at once.
trainerNpc, trainerCap = city, 8
Fire("TRAINER_SHOW")
assert(ns.db.classTrainerCaps[city] == 8, "the trainer window's cap was learned")
assert(
	ns.NearbyServices.Sections(world)[1].rows[1].npc.id == unknown,
	"a learned cap below the player's level drops that trainer from the built group"
)

print("trainer_cap_refresh_spec: ok")
