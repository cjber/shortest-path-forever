-- Recorded from a real client scan log (`/path debug`) on WoW Forever build 70862 at Stormwind's flight master,
-- Alliance night elf, 18 slots. `type` is TaxiNodeGetType, `state` is the C_TaxiMap node state. Every undiscovered
-- point was DISTANT, state 2, with isUndiscovered nil, so the fixture records no isUndiscovered field for them.
return {
	uiMap = 1463,
	slots = {
		{ slot = 1, nodeID = 2, name = "Stormwind", type = "CURRENT", state = 0 },
		{ slot = 2, nodeID = 4, name = "Sentinel Hill", type = "REACHABLE", state = 1 },
		{ slot = 3, nodeID = 5, name = "Lakeshire", type = "DISTANT", state = 2 },
		{ slot = 4, nodeID = 6, name = "Ironforge", type = "REACHABLE", state = 1 },
		{ slot = 5, nodeID = 7, name = "Menethil Harbor", type = "REACHABLE", state = 1 },
		{ slot = 6, nodeID = 8, name = "Thelsamar", type = "REACHABLE", state = 1 },
		{ slot = 7, nodeID = 12, name = "Darkshire", type = "DISTANT", state = 2 },
		{ slot = 8, nodeID = 14, name = "Southshore", type = "DISTANT", state = 2 },
		{ slot = 9, nodeID = 16, name = "Refuge Pointe", type = "DISTANT", state = 2 },
		{ slot = 10, nodeID = 19, name = "Booty Bay", type = "DISTANT", state = 2 },
		{ slot = 11, nodeID = 43, name = "Aerie Peak", type = "DISTANT", state = 2 },
		{ slot = 12, nodeID = 45, name = "Nethergarde Keep", type = "DISTANT", state = 2 },
		{ slot = 13, nodeID = 66, name = "Chillwind Camp", type = "DISTANT", state = 2 },
		{ slot = 14, nodeID = 67, name = "Light's Hope Chapel", type = "DISTANT", state = 2 },
		{ slot = 15, nodeID = 71, name = "Morgan's Vigil", type = "DISTANT", state = 2 },
		{ slot = 16, nodeID = 74, name = "Thorium Point", type = "DISTANT", state = 2 },
		{ slot = 17, nodeID = 3207, name = "zzOLDRiverglades, Farholde Keep", type = "DISTANT", state = 2 },
		{ slot = 18, nodeID = 3276, name = "Farholde Keep", type = "DISTANT", state = 2 },
	},
}
