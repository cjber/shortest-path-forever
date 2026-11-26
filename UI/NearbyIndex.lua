---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end

---@alias SPFNearbyIndexDone fun(itemNames: table, itemLevels: table, index: table, vendorItems: table)
---@alias SPFNearbyIndexFailed fun(error: any)
---@alias SPFNearbyIndexRun fun(read: table, context: table, done: SPFNearbyIndexDone, failed: SPFNearbyIndexFailed)
---@class SPFNearbyIndexContext
---@field Tiered table<string, boolean>
---@field VendorGroups SPFNearbyGroup[]
---@field Services table[]
---@field Roles SPFNearbyRolesAPI
---@field VendorKeys fun(itemID: integer, class: integer, subClass: integer): string[]
---@class SPFNearbyIndexAPI
---@field Assemble SPFNearbyIndexRun
local Index = {}
ns.NearbyIndex = Index

-- The QuestieDB read is large enough to yield between items, spawns and mailboxes. The parent module owns the
-- finished tables and group presentation; this module owns the producer and its frame-budgeted coroutine.
---@param read SPFNearbyQuestieRead
---@param context SPFNearbyIndexContext
---@param done SPFNearbyIndexDone
---@param failed SPFNearbyIndexFailed
function Index.Assemble(read, context, done, failed)
	local itemNames, itemLevels, index, vendorItems = {}, {}, {}, {}
	local co = coroutine.create(function()
		-- Every item QuestieDB says a vendor sells, with what this list groups it by.
		for itemID, item in pairs(read.items) do
			itemNames[itemID] = item.name
			local keys = context.VendorKeys(itemID, item.class, item.subClass)
			for _, npc in ipairs(item.vendors) do
				for _, key in ipairs(keys) do
					local byNpc = vendorItems[key]
					if not byNpc then
						byNpc = {}
						vendorItems[key] = byNpc
					end
					local items = byNpc[npc]
					if not items then
						items = {}
						byNpc[npc] = items
					end
					items[#items + 1] = itemID
				end
			end
			for _, key in ipairs(keys) do
				if context.Tiered[key] then
					itemLevels[itemID] = item.level or 0
				end
			end
			coroutine.yield()
		end
		local classIds = context.Roles.ClassTrainerIDs(rawget(_G, "TweaksForever"), true)
		local classID = context.Roles.PlayerClass()
		-- Every NPC the read kept, in each group its flags, its goods, its training and its role put it in.
		for id, row in pairs(read.npcs) do
			local keys = {}
			for _, service in ipairs(context.Services) do
				local flag = read.flags[service.flag]
				if type(flag) == "number" and bit.band(row.flags, flag) ~= 0 then
					keys[#keys + 1] = service.key
				end
			end
			for _, group in ipairs(context.VendorGroups) do
				if vendorItems[group.key] and vendorItems[group.key][id] then
					keys[#keys + 1] = group.key
				end
			end
			context.Roles.AddKeys(keys, id, classIds, classID)
			local skill = ns.ProfessionTrainers and ns.ProfessionTrainers[id]
			if skill then
				keys[#keys + 1] = "profession:" .. skill
			end
			if #keys > 0 then
				for _, spawn in ipairs(row.spawns) do
					local map, x, y = spawn[1], spawn[2], spawn[3]
					local world = ns.WorldPoint(map, x, y)
					if world then
						local place = {
							id = id,
							npc = id,
							name = row.name,
							title = row.title,
							map = map,
							x = x,
							y = y,
							world = world,
						}
						for _, key in ipairs(keys) do
							index[key] = index[key] or {}
							index[key][#index[key] + 1] = place
						end
					end
					coroutine.yield()
				end
			end
			coroutine.yield()
		end
		-- Static mailboxes need the zone projection owned by Core/PlanContext.lua. Partial consumers can omit that service.
		if ns.ZoneMap then
			for _, mailbox in ipairs(ns.Mailboxes or {}) do
				-- Mailboxes are continent world yards; the zone map under each gives the place its map position.
				local uiMap, position = ns.ZoneMap(mailbox.map, mailbox.x, mailbox.y)
				local x, y
				if position then
					x, y = position:GetXY()
				end
				local world = uiMap and ns.WorldPoint(uiMap, x, y)
				if world then
					local place = {
						id = mailbox.id,
						name = ns.L["Mailbox"],
						map = uiMap,
						x = x,
						y = y,
						world = world,
					}
					index.mailbox = index.mailbox or {}
					index.mailbox[#index.mailbox + 1] = place
				end
				coroutine.yield()
			end
		end
		done(itemNames, itemLevels, index, vendorItems)
	end)
	local function Pump()
		-- A large saved read takes only a few milliseconds of CPU, but waiting for Path.Busy can starve it
		-- for the whole login replan. Give the index its existing 1 ms slice independently of the planner's
		-- own frame budget, so both make progress without changing either budget.
		if InCombatLockdown() then
			C_Timer.After(0.1, Pump)
			return
		end
		local finish = debugprofilestop() + 1
		repeat
			local ok, err = coroutine.resume(co)
			if not ok then
				failed(err)
				return
			end
			if coroutine.status(co) == "dead" then
				return
			end
		until debugprofilestop() >= finish
		C_Timer.After(0, Pump)
	end
	C_Timer.After(0, Pump)
end
