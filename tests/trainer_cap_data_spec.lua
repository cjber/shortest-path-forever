local ForeverCore = dofile("tests/forever_core.lua")
local env = setmetatable({}, { __index = _G })
ForeverCore.load(env, "ForeverCore", { "Core/Text.lua" })
local ns = {}
setfenv(assert(loadfile("Data/Services.lua")), env)("ShortestPathForever", ns)

local caps = assert(ns.ClassTrainerCaps, "the generated services include class trainer caps")
assert(caps[925] == 8, "Brother Sammuel's direct trainer rows cap at level 8")
assert(caps[928] == 60, "Lord Grayson Shadowbreaker's direct trainer rows cap at level 60")
assert(caps[4988] == 60, "the World Paladin Trainer's template rows cap at level 60")
assert(caps[244808] == nil, "Aramis Hammerhand has no cap in classic-db")

print("trainer_cap_data_spec: ok")
