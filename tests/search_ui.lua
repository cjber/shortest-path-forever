-- Exercise the real route layers, tracker, Guide and compass against the offline client fixture.
local dir = arg[0]:match("^(.*)/") or "tests"
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [[
setMapShown(true)
posX, posY, posMap, facing = 0, 0, 1, 0
mapID, cursorX, cursorY, shiftDown = 1414, 0.5, 0.496, true
ns.db.tracker, ns.db.compass = false, true
-- These checks read the native waypoint as the journey's guidance, so every bend is marked and the guide writes and
-- tracks the client's marker at each bend.
ns.db.guideStops = false
-- Zoomed in on a zone-sized canvas, so the dots between here and a 100-yard goal clear the stop gaps (#51).
zoom, canvas.width, canvas.height = 1, 10000, 7000
-- This check answers the walking search itself.
path.auto = false
local function batches() return path.waiting(path.batches) end
local function jobs() return path.waiting(path.finds) end
local splitRoute, fromMid = false, false
ns.Planner.Plan = function(o)
 if o.feasibleOnly then return nil end
 if fromMid then
  -- Planned again from the bend: the step left is the same walk on.
  return {now=o.now, arrive=o.now+50000, legs={
   {mode="walk", from=o.from, to=o.to, yards=350, depart=o.now, arrive=o.now+50000},
  }}
 end
 if splitRoute then
  local mid = {map=1, x=50, y=40}
  return {now=o.now, arrive=o.now+100000, legs={
   {mode="walk", from=o.from, to=mid, yards=350, depart=o.now, arrive=o.now+50000},
   {mode="walk", from=mid, to=o.to, yards=350, depart=o.now+50000, arrive=o.now+100000},
  }}
 end
 return {now=o.now, arrive=o.now+200000, legs={{mode="walk", from=o.from, to=o.to,
  yards=1400, depart=o.now, arrive=o.now+200000}}}
end
assert(clickHandlers[1](map, "LeftButton"))
local tracker, mini = ShortestPathForeverObjectiveTracker, ShortestPathForeverMinimapRoute
local routeTemplate, goalTemplate = "ShortestPathForeverRoutePinTemplate", "ShortestPathForeverGoalPinTemplate"
local spinner = tracker.Spinner
assert(spinner.template == "SpinnerTemplate")
assert(spinner.Ring.atlas == "Spinner_Ring" and spinner.Sparks.atlas == "Spinner_Sparks")
assert(spinner.Sparks.blendMode == "ADD")
assert(spinner.Ring.allPoints == spinner and spinner.Sparks.allPoints == spinner)
assert(spinner.width == 16 and spinner.height == 16)
assert(spinner.anchor[1] == "LEFT" and spinner.anchor[2] == tracker.Header.Text)
assert(spinner.anchor[3] == "LEFT" and spinner.anchor[4] == tracker.Header.Text:GetStringWidth() + 6)
assert(spinner.anchor[5] == 0, "center vertically on the header text")
assert(spinner.Anim.looping == "REPEAT" and #spinner.Anim.animations == 2)
for i, rotation in ipairs(spinner.Anim.animations) do
 assert(rotation.kind == "Rotation" and rotation.Duration == 2 and rotation.Degrees == -360)
 assert(rotation.Order == 1 and rotation.Target == (i == 1 and spinner.Ring or spinner.Sparks))
end
local function pulse(owner, playing)
 local layer = assert(owner.strokeLayer)
 assert(layer.animation:IsPlaying() == playing)
 assert(not layer.scripts.OnUpdate, "pulsing must use native animation, never a frame script")
 if playing then
  assert(owner.used > 0)
  assert(layer.animation.owner == layer and layer.animation.looping == "BOUNCE")
  local alpha = layer.animation.animations[1]
  assert(#layer.animation.animations == 1 and alpha.kind == "Alpha")
  assert(alpha.FromAlpha == 0.8 and alpha.ToAlpha == 0.35 and alpha.Duration == 0.6)
  assert(alpha.Smoothing == "IN_OUT", "ease both ends of the 1.2-second pulse")
  for i=1,owner.used do
   assert(owner.lines[i].parent == layer and owner.underlines[i].parent == layer)
  end
 else
  assert(layer.alpha == 1, "settling restores full stroke opacity")
 end
end
local function drawn(loading)
 assert(#active[routeTemplate] == 1 and mini.used > 0)
 assert(select(5, ns.JourneyInfo()) == loading)
 assert(spinner.Anim:IsPlaying() == loading and spinner:IsShown() == loading)
 local pin = active[routeTemplate][1]
 pulse(pin, loading)
 pulse(mini, loading)
 assert(mini.Goal.parent == Minimap and active[goalTemplate][1] ~= pin)
 assert(waypoint and ns.GuideTargets())
 return pin
end
local function tick(seconds)
 T = T + seconds
 local driver = ShortestPathForeverJourneyDriver
 driver.scripts.OnUpdate(driver, seconds)
end
local function ready()
 for _, batch in ipairs(batches()) do path.costs(batch, 1400) end
end
local function finish()
 for _, job in ipairs(jobs()) do path.finish(job, {job.from, job.to}, 1400) end
end
local function begin()
 ns.ClearJourney()
 splitRoute = false
 assert(clickHandlers[1](map, "LeftButton"))
end
-- A search shows the goal and a "finding" row, and nothing guides until a walk is measured. Once the endpoint costs
-- are in, the rough route from the baked hub costs is drawn, pulsing, though nothing follows it.
local function searching(rough)
 if rough then
  assert(#active[routeTemplate] == 1 and mini.used > 0, "the rough route is drawn")
 else
  assert(#(active[routeTemplate] or {}) == 0 and mini.used == 0)
 end
 assert(#active[goalTemplate] == 1 and not mini.Goal.hidden, "only the goal pins are drawn")
 assert(not waypoint and not ns.GuideTargets())
 assert(not ShortestPathForeverCompass or not ShortestPathForeverCompass:IsShown())
 local block = tracker:GetExistingBlock("journey")
 assert(block and block.HeaderText:GetText():find("Journey to ", 1, true))
 assert(#tracker.blocks[1].rows == 1 and tracker.blocks[1].rows[1].grey)
 assert(tracker.blocks[1].rows[1].text == "Finding the fastest way…")
 assert(tracker.Header.Text:GetText() == "Journey")
 assert(spinner.Anim:IsPlaying() and spinner:IsShown())
 pulse(mini, rough)
end
local function hiddenRoute()
 searching(false)
end
local function roughRoute()
 searching(true)
end
hiddenRoute()
for _, batch in ipairs(batches()) do
 path.costs(batch, 1400)
 roughRoute()
end
assert(#jobs() == 1)
finish()
drawn(false)
assert(tracker.blocks[1].rows[1].key == 1 and tracker.Header.Text:GetText():find("yd",1,true))
assert(not spinner.Anim:IsPlaying() and spinner.hidden)

-- Even a long search guides nowhere until the first walk is measured; the rough route draws once the endpoints
-- are costed.
for _, replace in ipairs({false, true}) do
 begin()
 hiddenRoute()
 tick(3.1)
 hiddenRoute()
 splitRoute = replace
 ready()
 roughRoute()
 assert(#jobs() > 0)
 finish()
 drawn(false)
 assert(not ns.JourneyStatus())

 -- Background replans keep the existing route steady, including while replacement walks are pending.
 posY = 60
 tick(5)
 assert(ns.JourneyStatus() and #batches() > 0)
 drawn(false)
 ready()
 assert(ns.JourneyStatus() and #jobs() > 0)
 drawn(false)
 finish()
 assert(not ns.JourneyStatus())
 drawn(false)
 posY = 0
end

-- A repeated destination keeps an unfinished search private.
begin()
tick(3.1)
hiddenRoute()
assert(clickHandlers[1](map, "LeftButton"))
assert(ns.JourneyStatus())
hiddenRoute()

-- Clearing a measured journey releases hidden world-map pins and stops animations.
begin()
ready()
finish()
local released = drawn(false)
setMapShown(false)
ns.ClearJourney()
assert(released.paths == nil, "clearing while the map is closed releases pooled journey geometry")
pulse(released, false)
pulse(mini, false)
assert(not spinner.Anim:IsPlaying() and not spinner:IsShown())
assert(mini.Goal.hidden and not ns.GuideTargets())
assert(not mini.scripts.OnUpdate)

-- forever-core#795: walking on with the same steps changes the section's text, never its layout. Finishing a step
-- lays it out once; the timed replan from where you stand numbers the same steps from 1 again and must not.
setMapShown(true)
begin()
splitRoute = true
ready()
finish()
drawn(false)
local dirty, markDirty = 0, tracker.MarkDirty
tracker.MarkDirty = function(self) dirty = dirty + 1 return markDirty(self) end
local function settle() ready() finish() end
local function rowKeys()
 local keys = {}
 for _, row in ipairs(tracker.blocks[1].rows) do keys[#keys + 1] = tostring(row.key) end
 return table.concat(keys, ",")
end
assert(rowKeys() == "1,2", rowKeys())
for step = 1, 6 do
 posX, posY = step * 5, step * 4
 tick(0.6)
 settle()
end
assert(dirty == 0, "walking the same steps laid the section out " .. dirty .. " times")
posX, posY, fromMid = 50, 40, true
tick(0.6)
settle()
assert(rowKeys() == "1", "the finished step leaves: " .. rowKeys())
local finished = dirty
assert(finished == 1, "finishing a step lays the section out once, not " .. finished)
for step = 1, 12 do
 posX = 50 + step
 tick(0.6)
 settle()
end
assert(rowKeys() == "1" and dirty == finished, "the replan from here laid out the same step again: " .. dirty)

-- A new goal's search lists none of the steps of the journey it replaces, under the new goal's title, until its own
-- plan lands (#1107): the tracker and the goal pin's tooltip read the same rows.
local oldStep = tracker.blocks[1].rows[1].text
cursorY = 0.49
assert(clickHandlers[1](map, "LeftButton"))
assert(ns.JourneyStatus() and spinner:IsShown(), "the new goal is searching")
for _ = 1, 4 do
 local title, rows = ns.JourneyInfo()
 assert(title and title:find("Journey to ", 1, true))
 assert(#rows == 1 and rows[1].key == "searching", "the replaced journey's steps are gone: " .. tostring(rows[1].text))
 local shown = tracker.blocks[1].rows
 assert(#shown == 1 and shown[1].text == "Finding the fastest way…" and shown[1].text ~= oldStep)
 tick(0.6)
end
fromMid, splitRoute = false, false
settle()
assert(not ns.JourneyStatus() and not tracker.blocks[1].rows[1].grey, "the new route replaces it")
assert(not spinner:IsShown())
tracker.MarkDirty = markDirty
ns.ClearJourney()

assert(#errors == 0, table.concat(errors, "\n"))
print("search_ui: Group Finder spinner, private guesses, measured guidance and silent replans: ok")
]]))()
