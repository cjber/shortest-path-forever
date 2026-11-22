local ForeverCore = dofile("tests/forever_core.lua")
local handlers = {}
local aramis, other = 244808, 246152
local target = aramis
local level = 26
local filters = { available = true, unavailable = true, used = true }
-- GetTrainerServiceInfo returns name, rank, service type and whether a header is expanded; a header has no level.
local services = {
	{ "Holy", "header", nil },
	{ "First spell", "used", 4 },
	{ "Last spell", "unavailable", 12 },
	{ "Middle spell", "available", 8 },
}
local env = setmetatable({
	CreateFrame = function()
		local registered = {}
		return {
			RegisterEvent = function(_, event)
				registered[#registered + 1] = event
			end,
			SetScript = function(_, script, handler)
				assert(script == "OnEvent")
				for _, event in ipairs(registered) do
					handlers[event] = handler
				end
			end,
		}
	end,
	UnitClass = function()
		return "Paladin", "PALADIN", 2
	end,
	UnitLevel = function()
		return level
	end,
	UnitGUID = function(unit)
		assert(unit == "target")
		return ("Creature-0-1-2-3-%d-000000000A"):format(target)
	end,
	GetNumTrainerServices = function()
		return #services
	end,
	GetTrainerServiceTypeFilter = function(filter)
		return filters[filter]
	end,
	GetTrainerServiceInfo = function(index)
		local service = services[index]
		return service[1], "", service[2], true
	end,
	GetTrainerServiceLevelReq = function(index)
		return services[index][3]
	end,
}, { __index = _G })
env._G = env
ForeverCore.load(env, "ForeverCore", { "Core/Text.lua" })
local ns = {
	db = {},
	ClassTrainers = { [aramis] = 2, [other] = 2 },
	Init = function(fn)
		fn()
	end,
}
setfenv(assert(loadfile("UI/NearbyRoles.lua")), env)("ShortestPathForever", ns)

assert(ns.NearbyRoles.ClassTrainerIDs()[aramis], "Aramis is offered before his cap is known")
local show = assert(handlers.TRAINER_SHOW, "the trainer window event is registered")
show(nil, "TRAINER_SHOW")
assert(ns.db.classTrainerCaps[aramis] == 12, "the event saves the highest requirement under the target's NPC ID")
assert(not ns.NearbyRoles.ClassTrainerIDs()[aramis], "the saved cap rules out Aramis for a level 26 paladin")
level = 12
assert(ns.NearbyRoles.ClassTrainerIDs()[aramis], "a trainer is still offered at their cap")

target = other
filters.unavailable = false
show(nil, "TRAINER_SHOW")
assert(ns.db.classTrainerCaps[other] == nil, "a filtered list does not establish a cap")
filters.unavailable = true
services = {}
show(nil, "TRAINER_SHOW")
assert(ns.db.classTrainerCaps[other] == nil, "an empty list does not establish a cap")

print("trainer_cap_learning_spec: ok")
