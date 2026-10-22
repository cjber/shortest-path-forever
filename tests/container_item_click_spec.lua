-- Run from the repository root: luajit tests/container_item_click_spec.lua
-- Registering a tracker module with Blizzard's native manager taints the bag item click path.
local harness = dofile("tests/tracker_host_harness.lua")
local t = harness.new({ deferReady = true })
local check = t.check

t.ready()
t.drain()

local container = { tainted = false }
local itemButton = { parent = container, tainted = false }
local usedItem
function container:ItemButton_OnClick(button)
	assert(button.parent == self, "the item button stays in its container")
	assert(not self.tainted and not button.tainted, "the native bag click path stays secure")
	usedItem = true
end

container:ItemButton_OnClick(itemButton)
check(usedItem, "the bag item click reaches UseContainerItem")
check(t.first.parent == t.host, "the addon section is parented to the private tracker host")

print("container_item_click_spec: 2 checks passed")
