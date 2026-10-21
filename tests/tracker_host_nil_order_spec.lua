-- A companion addon may attach a section with no uiOrder of its own (SkillUp's profession reagents do). The layout
-- sort must complete, keep registration order among the ordered sections and place the unordered one last.
local harness = dofile("tests/tracker_host_harness.lua")
local t = harness.new({ deferReady = true })
local check, drain = t.check, t.drain
local first, second = t.first, t.second
local unordered = t.module(nil)
check(unordered.uiOrder == nil, "the companion section really has no uiOrder")
t.ready()
drain()
check(first.point[5] == 0 and second.point[5] == -90, "ordered sections still follow uiOrder")
check(unordered.point and unordered.point[5] == -180, "the section without a uiOrder follows the ordered ones")
check(unordered.updates == 1, "the section without a uiOrder is laid out once")
print("tracker_host_nil_order_spec: ok")
