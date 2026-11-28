-- The RestedXP bridge can select each step without pausing on Shortest Path's waypoints (#1390).
local boot = assert(loadfile("tests/tomtom_arrow_driver.lua"))()
local c = boot({ tomtomArrow = true, restedXPBridge = true }, true)
local rxp = c.env.RXP

for index = 1, 4 do
	local element =
		{ zone = 1, x = 50 + index * 5, y = 50, title = "RXP Step " .. index, arrow = true, step = { active = true } }
	rxp.arrowFrame.element, rxp.activeWaypoints = element, { element }
	rxp:UpdateMap()
	c.driver.path.settle()
	rxp.DrawArrow()
	c.runTimers()
end
assert(c.API.CurrentStop("RestedXP") == 1, "Shortest Path still plans the guide journey")
local selected = c.tomtom.Arrow()
assert(
	selected
		and selected.source == "RXPGuides"
		and selected.title == "RXP Step 4"
		and not c.crazy.hidden
		and c.crazy.alpha > 0
		and not c.bridge.paused,
	"the bridge still selects and shows the arrow after several steps"
)
print("tomtom RestedXP bridge steps: ok")
