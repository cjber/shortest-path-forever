-- Run from the repository root: luajit tests/core_dependency_spec.lua
-- Shortest Path Forever requires ForeverCore. This spec covers the two places the handover is the addon's: the
-- feature checks Core/Require.lua makes before it hands one boolean to the shared Core/ForeverRequire.lua warning
-- (whose naming and plural rules ForeverCore's own tests/forever_require_spec.lua covers), and the services it
-- registers with core at load.
local TOC = dofile("tests/toc_fields.lua").read("ShortestPathForever.toc")
assert(TOC["X-Forever-Icon"], "the TOC declares X-Forever-Icon")
assert(TOC["X-Forever-Core"], "the TOC declares the core it ships")

-- The TOC, the bundle and the pin are the same ForeverCore.
local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end
local pin = read("tools/forever-core.txt"):gsub("%s+$", "")
assert(TOC["X-Forever-Core"] == pin, "the TOC records the pinned core, " .. pin)
assert(
	read(".pkgmeta"):find("releases/download/" .. pin .. "/ForeverCore-" .. pin .. "-forever.zip", 1, true),
	"the package bundles the pinned core, " .. pin
)

-- The client's addon list: this addon, which requires ForeverCore, and ForeverCore itself.
local function Addons()
	local entries = {
		{
			name = "ShortestPathForever",
			title = TOC["Title"],
			core = TOC["X-Forever-Core"],
			deps = { "ForeverCore" },
		},
		{ name = "ForeverCore", title = "Forever Core", core = pin, deps = {} },
	}
	local function At(index)
		return entries[index]
	end
	return {
		GetAddOnMetadata = function(addon, field)
			for _, entry in ipairs(entries) do
				if addon == entry.name or addon == entry.name:lower() then
					if field == "Title" then
						return entry.title
					end
					if field == "X-Forever-Core" then
						return entry.core
					end
					return TOC[field]
				end
			end
		end,
		GetNumAddOns = function()
			return #entries
		end,
		GetAddOnInfo = function(index)
			local entry = At(index)
			if entry then
				return entry.name, entry.title
			end
		end,
		IsAddOnLoaded = function(index)
			return At(index) ~= nil
		end,
		GetAddOnEnableState = function(index)
			return At(index) and 2 or 0
		end,
		-- The client returns a dependency list as varargs, never a table.
		GetAddOnDependencies = function(index)
			local entry = At(index)
			if entry then
				return unpack(entry.deps)
			end
		end,
	}
end

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
		C_AddOns = Addons(),
		UnitName = function()
			return "Player"
		end,
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
	-- The TOC loads the shared warning before the addon's own Require, which calls it.
	load("Core/ForeverRequire.lua")
	load("Core/Require.lua")
	if not ns.broken then
		registered = { spec = nil }
		env.ForeverCore = {
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

-- A ForeverCore missing a member this addon calls stops the addon's own files with one line in the error frame,
-- never chat. The API kit and the tracker section and line each arrived after API 1.
local missing, missingLines = Load(nil)
assert(missing.broken == true and missing.core == nil, "a missing ForeverCore stops the addon")
assert(#missingLines == 1, "one line in the error frame")
local noKit, noKitLines = Load({ TrackerSection = {}, TrackerLine = {} })
assert(noKit.broken == true, "a ForeverCore without the API kit stops the addon too")
assert(#noKitLines == 1, "one line in the error frame")
local noSection, noSectionLines = Load({ APIKit = { Hub = function() end, NotReady = function() end } })
assert(noSection.broken == true, "a ForeverCore without the tracker section stops the addon too")
assert(
	noSectionLines[1] == "Shortest Path Forever could not start. Reinstall Shortest Path Forever to fix this.",
	noSectionLines[1]
)
-- The step markers arrived in ForeverCore 1.11.0: without them the addon's own Numbers art is gone and there is
-- nothing to draw a step's marker with.
local noArt, noArtLines = Load({
	APIKit = { Hub = function() end, NotReady = function() end },
	TrackerSection = { Create = function() end, UpdateText = function() end },
	TrackerLine = { SetInteractive = function() end },
	Art = { minor = 1, Icon = function() end },
})
assert(noArt.broken == true, "a ForeverCore without the step markers stops the addon too")
assert(#noArtLines == 1, "one line in the error frame")

-- Every member this addon calls is there: the addon runs, says nothing, and registers its services once: the report
-- title and its own report lines.
local ns, quiet, registered, attached = Load({
	APIKit = { Hub = function() end, NotReady = function() end },
	TrackerSection = { Create = function() end, UpdateText = function() end },
	TrackerLine = { SetInteractive = function() end },
	Art = { minor = 2, Marker = function() end, Ring = function() end, Diamond = function() end },
})
assert(quiet and #quiet == 0, "a complete ForeverCore runs the addon and says nothing")
assert(ns.core ~= nil, "the addon keeps its ForeverCore context")
assert(ns.Icon == TOC["X-Forever-Icon"], "the addon reads its identity icon from the TOC")
assert(ns.broken == nil, "a complete ForeverCore leaves the addon unbroken")
assert(registered.name == "ShortestPathForever", "it registers under its addon name")
assert(registered.spec.title == "Shortest Path report", "with its own report title")
assert(type(registered.spec.lines) == "function", "and its own report lines")
assert(attached == ns.db, "the saved table is attached once it loads")

-- The client loads ForeverCore first because the TOC declares it.
local toc = assert(io.open("ShortestPathForever.toc", "rb")):read("*a")
assert(toc:find("## Dependencies: ForeverCore", 1, true), "the TOC declares ForeverCore")

print("core_dependency_spec: ok")
