-- ForeverCore, the addon every Forever addon requires, loaded the way the client loads it: the files its TOC lists,
-- in order, from the checkout the FOREVER_CORE environment variable names. Local runs default to the sibling checkout
-- ../forever-core; CI checks the ref in tools/forever-core.txt out into forever-core/.
--
--   local core = dofile("tests/forever_core.lua")
--   local ForeverCore = core.install(env, { "Core/SafeCall.lua", "Expose.lua" })
--
-- `install` loads only the named files (every file when nil) into its own namespace and returns the ForeverCore
-- global, so a spec can register through it. `load` fills an environment and a namespace a harness already has.
local ForeverCore = {}

local DEFAULT_DIRECTORY = "../forever-core"

local function Exists(path)
	local file = io.open(path .. "/ForeverCore.toc", "r")
	if file then
		file:close()
		return true
	end
	return false
end

-- The checkout, as FOREVER_CORE names it. A relative path is read from the working directory first, then from
-- GITHUB_WORKSPACE, because the packaged specs run from a scratch folder rather than the repository root.
---@return string
function ForeverCore.directory()
	local configured = os.getenv("FOREVER_CORE")
	local candidates = {}
	if configured and configured ~= "" then
		candidates[#candidates + 1] = configured
		if configured:sub(1, 1) ~= "/" then
			local workspace = os.getenv("GITHUB_WORKSPACE")
			if workspace and workspace ~= "" then
				candidates[#candidates + 1] = workspace .. "/" .. configured
			end
		end
	else
		candidates[#candidates + 1] = DEFAULT_DIRECTORY
	end
	for _, path in ipairs(candidates) do
		local cleaned = path:gsub("/+$", "")
		if cleaned ~= "" and Exists(cleaned) then
			return cleaned
		end
	end
	error(
		"ForeverCore's checkout is not at "
			.. table.concat(candidates, " or ")
			.. "; set FOREVER_CORE to it (tools/forever-core.txt names the ref)"
	)
end

-- The files ForeverCore.toc lists, in its order, with forward slashes for loadfile.
---@param directory string
---@return string[]
function ForeverCore.files(directory)
	local files = {}
	for line in io.lines(directory .. "/ForeverCore.toc") do
		line = line:gsub("\r$", "")
		if not (line:match("^%s*$") or line:match("^%s*#")) then
			files[#files + 1] = line:gsub("\\", "/")
		end
	end
	return files
end

---@param names string[]?
---@return table<string, boolean>?
local function Wanted(names)
	if names == nil then
		return nil
	end
	local set = { ["Locales/enUS.lua"] = true }
	for _, name in ipairs(names) do
		set[name] = true
	end
	return set
end

-- Loads ForeverCore's Lua files into `env`, each with the one namespace, and returns that namespace. The caller fires
-- ForeverCore's ADDON_LOADED afterwards, as the client does before the addon's own. A TOC's XML entry is the client's
-- own to parse into frames and templates before the Lua beside it runs, so it is skipped here rather than loadfile'd.
---@param env table the fake client
---@param name? string the addon folder, "ForeverCore"
---@param names? string[] only these core files, in TOC order; every file when nil
---@param ns? table the namespace to fill, a new one when nil
---@return table
function ForeverCore.load(env, name, names, ns)
	local directory = ForeverCore.directory()
	local selected = Wanted(names)
	ns = ns or {}
	for _, path in ipairs(ForeverCore.files(directory)) do
		if selected == nil or selected[path] then
			-- Core's own quest section needs the full native tracker template; a spec without one skips that optional
			-- section, as core's own api_spec does. A spec with no GetLocale skips the translations after enUS, whose
			-- guard would stop on the missing client call.
			local native = env.ObjectiveTrackerFrame
			local translated = path:match("^Locales/") and path ~= "Locales/enUS.lua"
			local xml = path:match("%.xml$") ~= nil
			if not xml and (path ~= "UI/TrackerQuests.lua" or native ~= nil) then
				if not (translated and type(env.GetLocale) ~= "function") then
					local chunk = assert(loadfile(directory .. "/" .. path), path)
					setfenv(chunk, env)
					chunk(name or "ForeverCore", ns)
				end
			end
			env.ObjectiveTrackerFrame = native
		end
	end
	return ns
end

-- Loads ForeverCore into `env` and a namespace of its own, and returns the global its TOC publishes.
---@param env table?
---@param names? string[]
---@return ForeverCoreAPI
function ForeverCore.install(env, names)
	env = env or _G
	ForeverCore.load(env, "ForeverCore", names)
	return assert(env.ForeverCore or _G.ForeverCore, "ForeverCore did not publish its global")
end

-- ForeverCore as an extra addon for the client simulator: the folder and its addon name, registered next to the
-- one under test so the TOC's dependency resolves to the real checkout.
---@return { [1]: string, [2]: string }[]
function ForeverCore.addons()
	return { { ForeverCore.directory(), "ForeverCore" } }
end

return ForeverCore
