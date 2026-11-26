-- The RestedXP bridge can select each step without pausing on Shortest Path's waypoints (#1390).
local boot = assert(loadfile("tests/tomtom_arrow_driver.lua"))()
local c = boot({ tomtomArrow = true, restedXPBridge = true }, true)
local rxp = c.env.RXP

for index = 1, 4 do
	local element = rxp.arrowFrame.element
	element.x = 50 + index * 5
	element.title = "RXP Step " .. index
	rxp:UpdateMap()
	c.driver.path.settle()
	c.bridgeStep(index)
	c.runTimers()
end
assert(c.API.CurrentStop("RestedXP") == 1, "Shortest Path still plans the guide journey")
local selected = c.tomtom.Arrow()
assert(
	selected and selected.source == "RXPGuides" and selected.title == "RXP Step 4" and not c.crazy.hidden,
	"the bridge still selects and shows the arrow after several steps"
)
print("tomtom RestedXP bridge steps: ok")
