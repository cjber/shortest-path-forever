local ForeverCore = dofile("tests/forever_core.lua")
local destination
local env = setmetatable({
	UnitClass = function()
		return "Paladin", "PALADIN", 2
	end,
	UnitLevel = function()
		return 26
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
			return { { npc = starter } }
		end,
	},
}
local ns = {
	db = {},
	ClassTrainers = { [starter] = 2, [city] = 2, [unknown] = 2 },
	ClassTrainerCaps = { [starter] = 8, [city] = 60 },
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

ns.NearbyServices.Request()
assert(ns.NearbyServices.State() == "ready", "the Nearby catalogue was built")
env.SlashCmdList.SPFNEAR("class")
assert(destination == city, "the level 26 paladin's journey skips the capped trainer and goes to the city trainer")
local world = ns.NearbyServices.PlayerWorld()
local sections = ns.NearbyServices.Sections(world)
assert(sections[1].rows[1].npc.id == city, "the Nearby class trainer row skips the capped trainer")
local candidates = ns.NearbyServices.Shortlist("class", world, 3)
assert(#candidates == 2 and candidates[2].id == unknown, "a trainer with an unknown cap is still offered")

print("trainer_cap_spec: ok")
