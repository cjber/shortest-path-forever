-- Every phrase a player reads goes through L, so it can be translated, and Locales/phrases.txt (the file a
-- translator copies) lists exactly the phrases the code uses.

local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end

-- A literal handed straight to one of the places the player reads it. `%s*` spans line breaks, so a call split
-- over lines by StyLua still counts.
local SINKS = {
	':SetText%(%s*"([^"]*)"',
	':SetFormattedText%(%s*"([^"]*)"',
	':SetHeader%(%s*"([^"]*)"',
	':CreateButton%(%s*"([^"]*)"',
	':CreateCheckbox%(%s*"([^"]*)"',
	':CreateTitle%(%s*"([^"]*)"',
	':AddLine%(%s*"([^"]*)"',
	':AddDoubleLine%(%s*"([^"]*)"',
	'AddMessage%(%s*"([^"]*)"',
	'GameTooltip_SetTitle%(%s*[%w_]+,%s*"([^"]*)"',
	'GameTooltip_Add%a*Line%(%s*[%w_]+,%s*"([^"]*)"',
	'Print%(%s*"([^"]*)"',
	'Print%(%s*string%.format%(%s*"([^"]*)"',
	-- UI/Settings.lua's rows and UI/Map.lua's filter menu: a saved-variable key, then the label.
	'Checkbox%(%s*"[%w_]+",%s*"([^"]*)"',
	'AddFilter%(%s*"[%w_]+",%s*"([^"]*)"',
}

-- Shown as they are on purpose: the addon's name, and `/path perf` and `/path debug` output.
local ALLOWED = {
	["Shortest Path Forever"] = true,
	["CPU profiling is unavailable on this client."] = true,
	["Memory accounting is unavailable on this client."] = true,
	["Ticks over 5 ms: %d"] = true,
	["CPU %s: %.3f ms"] = true,
	["Memory (collected): %.1f KB"] = true,
	["debug "] = true,
	["walking cost mismatch: planned %.1f, found %s"] = true,
	["map %s at %s, %s; ride: %s"] = true,
}

local shipped = {}
for line in io.lines("ShortestPathForever.toc") do
	local file = line:match("^([^#]%S*%.lua)%s*$")
	if file then
		shipped[#shipped + 1] = (file:gsub("\\", "/"))
	end
end
assert(#shipped > 20, "the TOC lists the addon's files")
assert(shipped[1] == "Locales/enUS.lua", "L exists before any file uses it")

local found = {}
for _, file in ipairs(shipped) do
	if not file:match("^Locales/") and not file:match("^Data/") then
		local text = read(file):gsub("%-%-[^\n]*", "")
		for _, sink in ipairs(SINKS) do
			for literal in text:gmatch(sink) do
				if literal:match("%a") and not ALLOWED[literal] then
					found[#found + 1] = string.format('%s: "%s" (wrap it in L[])', file, literal)
				end
			end
		end
	end
end
assert(#found == 0, "\n" .. table.concat(found, "\n"))

-- The middle dot joins two phrases; outside L a translation could not change it, so it goes through "%s · %s".
local joins = {}
for _, file in ipairs(shipped) do
	if not file:match("^Data/") and read(file):gsub("%-%-[^\n]*", ""):find('"%s*·%s*"') then
		joins[#joins + 1] = file .. ': a bare " · " (join through L["%s · %s"])'
	end
end
assert(#joins == 0, "\n" .. table.concat(joins, "\n"))

-- The guard itself still sees a bare literal.
local probe = 'GameTooltip_AddInstructionLine(GameTooltip, "Click to go")'
assert(probe:match(SINKS[11]) == "Click to go")

-- Locales/phrases.txt is what tools/phrases.py prints.
local pipe = assert(io.popen("python3 tools/phrases.py"))
local printed = pipe:read("*a")
assert(pipe:close(), "tools/phrases.py failed")
assert(printed ~= "" and printed == read("Locales/phrases.txt"), "run: python3 tools/phrases.py > Locales/phrases.txt")

-- A missing phrase reads as English. The template is a working translation file: in its own language it
-- replaces the English, in any other it changes nothing.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(ns.L["Journey"] == "Journey")
local template, count = read("Locales/phrases.txt"):gsub('\nL%["Journey"%] = "Journey"\n', '\nL["Journey"] = "Reise"\n')
assert(count == 1, "the template lists Journey")
for _, case in ipairs({ { "frFR", "Journey" }, { "deDE", "Reise" } }) do
	local env = setmetatable({
		GetLocale = function()
			return case[1]
		end,
	}, { __index = _G })
	setfenv(assert(loadstring(template)), env)("ShortestPathForever", ns)
	assert(ns.L["Journey"] == case[2] and ns.L["Boats"] == "Boats", case[1])
end

-- Every translation the TOC loads, read in its own client language: each line is a string and formats without error
-- given the arguments its English takes (a sample per placeholder). tools/check_locales.py checks that the
-- placeholders themselves match. The translations load straight after Locales/enUS.lua, before any file that reads
-- L while it loads (labels, and Nearby's reagent titles), or those would stay English.
local SAMPLE = { d = 7, i = 7, c = 65, o = 7, u = 7, x = 7, X = 7, e = 1.5, E = 1.5, f = 1.5, g = 1.5, G = 1.5 }
local function samples(english)
	local args = {}
	for spec in english:gsub("%%%%", ""):gmatch("%%[-+#0]*%d*%.?%d*(%a)") do
		args[#args + 1] = SAMPLE[spec] or "Stormwind"
	end
	return args
end
local translations = 0
for position = 2, #shipped do
	if shipped[position]:match("^Locales/") then
		assert(shipped[position - 1]:match("^Locales/"), shipped[position] .. " loads straight after Locales/enUS.lua")
	end
end
for _, file in ipairs(shipped) do
	local code = file:match("^Locales/(%a%a%a%a)%.lua$")
	if code and code ~= "enUS" then
		translations = translations + 1
		local own = {}
		assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", own)
		local untouched = {}
		assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", untouched)
		for _, case in ipairs({ { code, own }, { code == "deDE" and "frFR" or "deDE", untouched } }) do
			local env = setmetatable({
				GetLocale = function()
					return case[1]
				end,
			}, { __index = _G })
			setfenv(assert(loadfile(file)), env)("ShortestPathForever", case[2])
		end
		assert(next(rawget(untouched, "L")) == nil, file .. " changes nothing in another client language")
		local lines = 0
		for english, text in pairs(own.L) do
			lines = lines + 1
			assert(type(english) == "string" and type(text) == "string", file .. ": " .. tostring(english))
			local args = samples(english)
			if #args > 0 then
				local ok, err = pcall(string.format, text, unpack(args))
				assert(ok, string.format('%s: "%s" does not format: %s', file, text, tostring(err)))
				assert(pcall(string.format, english, unpack(args)), english)
			end
		end
		assert(lines > 0, file .. " translates something")
	end
end
assert(translations > 0, "the TOC loads the translations after Locales/enUS.lua")

-- The packager's CurseForge localization keyword would fail the release: CurseForge no longer serves translations.
local keyword = "@" .. "localization"
local grep = assert(io.popen("git grep -l -F '" .. keyword .. "'"))
local hits = grep:read("*a")
grep:close()
assert(hits == "", "remove the packager localization keyword from:\n" .. hits)

print("locales_spec: ok")
