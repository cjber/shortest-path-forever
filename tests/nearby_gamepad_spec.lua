-- Gamepad leaves the game's menus alone. Nearby tells the player why its panel needs a mouse and keyboard.
local h = dofile("tests/nearby_spec.lua")
local env = h.env
h.setGamepad(true)
local opens, entries = h.getMapOpens(), h.getMenuEntries()
env.SlashCmdList.SPFNEAR("")
assert(
	h.getMapOpens() == opens and h.getMenuEntries() == entries,
	"no map or menu opened by us under the gamepad interface"
)
env.WorldMapFrame = {
	IsShown = function()
		return true
	end,
}
env.SlashCmdList.SPFNEAR("")
assert(h.getMapOpens() == opens and h.getMenuEntries() == entries, "over an open map no menu of ours opens either")
assert(h.getPrinted()[#h.getPrinted()]:find("mouse and keyboard", 1, true), "it says what the services need")
h.setGamepad(false)
env.WorldMapFrame = nil
print(
	"nearby: installed QuestieDB contract, sliced loading, faction/class/profession grouping, "
		.. "real map-menu callbacks, UI-coordinate dispatch and gamepad guard: ok"
)
