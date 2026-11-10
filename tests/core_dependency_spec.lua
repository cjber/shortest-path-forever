-- Run from the repository root: luajit tests/core_dependency_spec.lua
-- Shortest Path Forever requires ForeverCore. This spec covers the two places the handover is the addon's: the
-- one-line stop for a ForeverCore older than API 1 or without the API kit, and the services it registers with core at
-- load.
local function Load(foreverCore)
	local lines, registered, attached, frames = {}, nil, nil, {}
	local function frame()
		local f = {}
		function f.RegisterEvent() end
		function f.UnregisterEvent() end
		function f:SetScript(name, fn)
			self[name] = fn
		end
		frames[#frames + 1] = f
		return f
	end
	local env = setmetatable({
		ForeverCore = foreverCore,
		UIErrorsFrame = {
			AddMessage = function(_, text)
				lines[#lines + 1] = text
			end,
		},
		CreateFrame = frame,
		C_Timer = {
			NewTicker = function()
				return { Cancel = function() end }
			end,
		},
		IsPlayerMoving = function()
			return false
		end,
		GetServerTime = function()
			return 100
		end,
		GetTime = function()
			return 1
		end,
	}, { __index = _G })
	env._G = env
	local ns = { Model = {} }
	local function load(file)
		setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
	end
	load("Locales/enUS.lua")
	load("Core/Require.lua")
	if not ns.broken then
		registered = { spec = nil }
		env.ForeverCore = {
			API = 1,
			APIKit = foreverCore.APIKit,
			Register = function(name, spec)
				registered.name, registered.spec = name, spec
				return {
					SafeCall = function(_, fn, ...)
						return pcall(fn, ...)
					end,
					Attach = function(db)
						attached = db
					end,
				}
			end,
		}
		-- Core/Require has already run; the real global is what Core/Core.lua reads.
		load("Core/Core.lua")
		for _, f in ipairs(frames) do
			if f.OnEvent then
				f:OnEvent("ADDON_LOADED", "ShortestPathForever")
			end
		end
	end
	return ns, lines, registered, attached
end

-- An older ForeverCore stops the addon's own files with one line in the error frame, never chat.
local broken, lines = Load(nil)
assert(broken.broken == true and broken.core == nil, "a missing ForeverCore stops the addon")
assert(#lines == 1 and lines[1]:find("ForeverCore", 1, true), "and says so in one error line")
local old, oldLines = Load({ API = 0 })
assert(old.broken == true and #oldLines == 1, "a ForeverCore older than API 1 stops the addon too")
local unkit, unkitLines = Load({ API = 1 })
assert(unkit.broken == true and #unkitLines == 1, "a ForeverCore without the API kit stops the addon too")

-- API 1 with the API kit registers the addon's services once: the report title and its own report lines.
local ns, quiet, registered, attached = Load({ API = 1, APIKit = {} })
assert(quiet and #quiet == 0, "API 1 runs the addon and says nothing")
assert(ns.core ~= nil, "the addon keeps its ForeverCore context")
assert(registered.name == "ShortestPathForever", "it registers under its addon name")
assert(registered.spec.title == "Shortest Path report", "with its own report title")
assert(type(registered.spec.lines) == "function", "and its own report lines")
assert(attached == ns.db, "the saved table is attached once it loads")

-- The client loads ForeverCore first because the TOC declares it.
local toc = assert(io.open("ShortestPathForever.toc", "rb")):read("*a")
assert(toc:find("## Dependencies: ForeverCore", 1, true), "the TOC declares ForeverCore")

print("core_dependency_spec: ok")
