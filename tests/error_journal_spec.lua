-- Run from the repository root: luajit tests/error_journal_spec.lua
-- ForeverCore's shared error journal and debug log live in ShortestPathForeverDB, attached at ADDON_LOADED once the
-- saved variables and their defaults are in, so the report lists earlier sessions' errors and the lines that led to
-- them after a /reload.
local ForeverCore = dofile("tests/forever_core.lua")

local function loadCore(saved)
	local frames = {}
	local env = setmetatable({
		ShortestPathForeverDB = saved,
		SlashCmdList = {},
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
		-- The client's clock for the shared log's lines, fixed so the spec is deterministic.
		GetTime = function()
			return 1.5
		end,
		date = function()
			return "2026-11-08 12:00:00"
		end,
		UnitFactionGroup = function()
			return "Alliance"
		end,
		geterrorhandler = function()
			return error
		end,
		seterrorhandler = function() end,
		strtrim = function(text)
			return (text:gsub("^%s+", ""):gsub("%s+$", ""))
		end,
		CreateFrame = function()
			local frame = {}
			function frame.RegisterEvent() end
			function frame.RegisterUnitEvent() end
			function frame.UnregisterEvent() end
			function frame:SetScript(name, fn)
				self[name] = fn
			end
			frames[#frames + 1] = frame
			return frame
		end,
	}, { __index = _G })
	ForeverCore.load(env, "ForeverCore")
	local function fire(event, name)
		for _, frame in ipairs(frames) do
			if frame.OnEvent then
				frame:OnEvent(event, name)
			end
		end
	end
	fire("ADDON_LOADED", "ForeverCore")
	local ns = { Model = {} }
	for _, file in ipairs({ "Locales/enUS.lua", "Core/Core.lua" }) do
		setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
	end
	fire("ADDON_LOADED", "ShortestPathForever")
	return ns
end

-- A first install, with no saved table at all: the load makes the journal and the log in ShortestPathForeverDB and
-- attaches them.
local ns = loadCore(nil)
local db = assert(ns.db, "the saved table was not made")
assert(type(db.errors) == "table", "the saved table has no error journal")
assert(type(db.log) == "table", "the saved table has no debug log")

-- An error caught by ns.core.SafeCall is recorded in the saved journal, which is where the next session reads it.
local ok = ns.core.SafeCall("error journal spec", function()
	error("error journal spec failure")
end)
assert(ok == false, "the failure was not caught")
local entry
for _, candidate in ipairs(db.errors) do
	if candidate.message:find("error journal spec failure", 1, true) then
		entry = candidate
	end
end
assert(entry, "the caught error did not reach the saved journal")
assert(entry.kind == "error" and entry.count == 1, "the journal entry is not one error")
assert(type(entry.firstSeen) == "number" and type(entry.lastSeen) == "number", "the journal entry has no times")

-- The log rides in the same saved table, so the lines that led to a bug survive a /reload too.
ns.core.Log("info", "error journal spec", "a line before the reload")
local logged
for _, line in ipairs(db.log.lines or {}) do
	if line:find("a line before the reload", 1, true) then
		logged = line
	end
end
assert(logged, "the log line did not reach the saved ring")
assert(logged:find("info error journal spec:", 1, true), "the saved line has no level and topic")

-- A table a previous session saved is the journal and the log this one keeps, and its entries reach the report as
-- earlier sessions' errors.
local saved = {
	errors = {
		{
			signature = "earlier\n",
			kind = "error",
			message = "error from an earlier session",
			stack = "",
			count = 2,
			firstSeen = 1,
			lastSeen = 2,
		},
	},
	log = {
		lines = { "2026-11-07 09:00:00 +12.0s info earlier: line from an earlier session" },
		pinned = false,
	},
}
local reloaded = loadCore(saved)
assert(reloaded.db == saved, "the saved table was replaced")
assert(reloaded.db.errors == saved.errors, "the journal is not the saved errors table")
assert(reloaded.db.log == saved.log, "the log is not the saved log table")
local earlier
for _, candidate in ipairs(reloaded.core.CaughtErrors()) do
	if candidate.message == "error from an earlier session" then
		earlier = candidate
	end
end
assert(earlier and earlier.fromSession == false, "an earlier session's error is missing from the report")
assert(earlier.count == 2, "the earlier session's count was lost")
local kept
for _, line in ipairs(reloaded.core.LogLines(10)) do
	if line:find("line from an earlier session", 1, true) then
		kept = line
	end
end
assert(kept, "an earlier session's log line is missing after the reload")

print("error_journal_spec: ok")
