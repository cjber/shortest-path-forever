-- Real frame/timer dispatch with a drawn journey, GC stopped so transient garbage cannot hide.
-- Run with luajit -joff tests/steady_spec.lua [report]. Client SetPoint stubs allocate their
-- recorded arguments too: an unchanged view must not call them in the first place.
-- Trace compilation allocates independently of addon work; measure the interpreter path.
jit.off()
local source = "local work = 0\n"
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open("tests/" .. part))
	source = source .. file:read("*a")
	file:close()
end
-- Count native output writes as work too, even when a stub itself does not allocate.
for _, signature in ipairs({
	"function f:SetPoint(...)",
	"function texture:SetPoint(...)",
	"function texture:SetRotation(v)",
	"function texture:SetAlpha(v)",
	"function f:SetAlpha(v)",
}) do
	local first = source:find(signature, 1, true)
	if first then
		local last = first + #signature - 1
		source = source:sub(1, last) .. " work = work + 1 " .. source:sub(last + 1)
	end
end
assert(loadstring(source .. [[
ns.db.debug = false
ns.db.destinationPin = true
ns.db.compass = true
posX, posY, posMap = 2000, 2000, 1
ns.StartJourney({map = 1, x = 2500, y = 2500, label = "Standing journey"})
path.settle()
ns.DestinationPinChanged()
-- A five-second replan checks changing cooldowns and sailings, and TravelTick updates
-- countdowns once a second. Those are timed work, not the unchanged per-frame path. Keep
-- their allocation and CPU visible separately rather than disabling them to pass the test.
local timedKB, timedWork = 0, 0
local replan = ns.JourneySearch.Replan
ns.JourneySearch.Replan = function(...)
 local memory, writes = collectgarbage("count"), work
 replan(...)
 timedKB = timedKB + collectgarbage("count") - memory
 timedWork = timedWork + work - writes
end
local progressWork = 0
local advance = ns.AdvanceJourneyProgress
ns.AdvanceJourneyProgress = function(...)
 progressWork = progressWork + 1
 return advance(...)
end
local stats = {}
local function call(fn, self, elapsed)
 local stat = stats[fn]
 if not stat then stat = {calls = 0, kb = 0, work = 0, worst = 0,
   key = debug.getinfo(fn, "S").short_src} stats[fn] = stat end
 local before, writes, start = collectgarbage("count"), work, os.clock()
 local scheduled, scheduledWork = timedKB, timedWork
 fn(self, elapsed)
 stat.worst = math.max(stat.worst, (os.clock() - start) * 1000)
 stat.kb = stat.kb + collectgarbage("count") - before - (timedKB - scheduled)
 stat.work = stat.work + work - writes - (timedWork - scheduledWork)
 stat.calls = stat.calls + 1
end
local function frame()
 T = T + 1/60
 for index = coreFrames + 1, #frames do
  local f = frames[index]
  if f:IsVisible() and f.scripts.OnUpdate then call(f.scripts.OnUpdate, f, 1/60) end
 end
 for index = coreTickers + 1, #tickers do
  local t = tickers[index]
  if not t.cancelled and T >= t.next then t.next = T + t.every call(t.fn) end
 end
 runPending()
end
for _, open in ipairs({false, true}) do
 setMapShown(open)
 for _ = 1, 2400 do frame() path.settle() end
 stats = {}
 collectgarbage("collect")
 collectgarbage("stop")
 -- Prime the attribution counters outside the measurement.
 for _ = 1, 120 do frame() end
 for _, stat in pairs(stats) do stat.calls, stat.kb, stat.work, stat.worst = 0, 0, 0, 0 end
 timedKB, timedWork, progressWork = 0, 0, 0
 local finds = #path.finds + #path.batches
 local before = collectgarbage("count")
 for _ = 1, 3600 do frame() end
 local growth = collectgarbage("count") - before
 collectgarbage("restart")
 print(string.format("map %s: %.6f KB/frame (%.3f KB total)", open and "open" or "closed", growth / 3600, growth))
 local steadyKB, steadyWork = 0, 0
 for _, stat in pairs(stats) do
  print(string.format("  %s: %d callbacks, %.3f KB, %d writes, %.3f ms worst",
   stat.key, stat.calls, stat.kb, stat.work, stat.worst))
  if stat.key ~= "Core/Core.lua" then
   steadyKB, steadyWork = steadyKB + stat.kb, steadyWork + stat.work
  end
 end
 print(string.format("  unchanged callbacks: %.6f KB/frame, %d writes; timed replans %.3f KB",
  steadyKB / 3600, steadyWork, timedKB))
 assert(#errors == 0, table.concat(errors, "\n"))
 if arg[1] ~= "report" then
  assert(steadyKB == 0, "unchanged frame/poll callbacks must allocate zero bytes")
  assert(steadyWork == 0, "unchanged frame/poll callbacks must not redraw")
  assert(progressWork == 0, "unchanged walking progress must not walk the legs again")
  assert(#path.finds + #path.batches == finds, "stationary endpoints must not be searched again")
 end
end
-- Exact changed inputs must wake output again after the quiet path has been exercised.
local before = work
posX = posX + 1
for _ = 1, 60 do frame() end
assert(work > before, "a changed position redraws guidance and minimap")
before = work
facing = facing + 0.1
for _ = 1, 60 do frame() end
assert(work > before, "a changed heading redraws directions")
before = work
zoom = 0.5
frame()
assert(work > before, "a changed map view redraws its pins")
ns.ClearJourney()
assert(#errors == 0, table.concat(errors, "\n"))
]]))()
