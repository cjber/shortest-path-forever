-- spf-1080: the zone map Hazards.ZoneAt would read for every 64 yd cell of the two continents, run-length encoded
-- per column, so the planner can ship it as data instead of asking C_Map per cell. Same lookup as ns.ZoneMap.
local CELL = 64
local function ZoneMap(map, x, y)
	local world = CreateVector2D(x, y)
	local uiMap, position = C_Map.GetMapPosFromWorldPos(map, world)
	if not uiMap then
		return 0
	end
	local info = C_Map.GetMapInfo(uiMap)
	if info and info.mapType ~= Enum.UIMapType.Zone then
		local zone = C_Map.GetMapInfoAtPosition(uiMap, position:GetXY())
		if zone and zone.mapType == Enum.UIMapType.Zone then
			local zoneMap = C_Map.GetMapPosFromWorldPos(map, world, zone.mapID)
			if zoneMap then
				uiMap = zoneMap
			end
		end
	end
	return uiMap
end
local lines, start = {}, debugprofilestop()
for _, box in ipairs({ { 0, -241, -106, 59, 53 }, { 1, -164, -131, 184, 85 } }) do
	local map, i0, j0, i1, j1 = box[1], box[2], box[3], box[4], box[5]
	for i = i0, i1 do
		local runs, last, count = {}, nil, 0
		for j = j0, j1 do
			local zone = ZoneMap(map, (i + 0.5) * CELL, (j + 0.5) * CELL)
			if zone == last then
				count = count + 1
			else
				if last then
					runs[#runs + 1] = last .. "x" .. count
				end
				last, count = zone, 1
			end
		end
		runs[#runs + 1] = last .. "x" .. count
		lines[#lines + 1] = "Z" .. map .. " " .. i .. " " .. j0 .. " " .. table.concat(runs, " ")
	end
end
lines[#lines + 1] = ("spf1080 zone cells done in %.0f ms, %d columns"):format(debugprofilestop() - start, #lines)
return table.concat(lines, "\n")
