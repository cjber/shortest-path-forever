-- Run from the repository root: luajit tests/quest_blob_spec.lua
-- The minimap's own quest area while the player stands in a held stop's area (#504): the area's inside, outside and
-- selected outside textures wear the bonus objective's gold, the edge ring around the whole minimap is left alone
-- (a gold ring there is a second, larger outline around the blue area). A client without the selected setter still
-- gets the ordinary area recoloured.
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local QUEST = {
	inside = "Interface\\Minimap\\UI-QuestBlobMinimap-Inside",
	outside = "Interface\\Minimap\\UI-QuestBlobMinimap-Outside",
	outsideSelected = "Interface\\Minimap\\UI-QuestBlobMinimap-OutsideSelected",
}
local BONUS = {
	inside = "Interface\\Minimap\\UI-BonusObjectiveBlob-Inside",
	outside = "Interface\\Minimap\\UI-BonusObjectiveBlob-Outside",
	outsideSelected = "Interface\\Minimap\\UI-BonusObjectiveBlob-OutsideSelected",
}

-- One stub Minimap and namespace; `selected` says whether this client has the selected-edge setter.
local function fixture(selected)
	local minimap = { sets = {} }
	local function record(name, value)
		minimap.sets[#minimap.sets + 1] = { name = name, value = value }
	end
	function minimap:SetQuestBlobInsideTexture(texture)
		self.inside = texture
		record("inside", texture)
	end
	function minimap:SetQuestBlobOutsideTexture(texture)
		self.outside = texture
		record("outside", texture)
	end
	if selected then
		function minimap:SetQuestBlobOutsideSelectedTexture(texture)
			self.outsideSelected = texture
			record("outsideSelected", texture)
		end
	end
	function minimap:SetQuestBlobRingTexture(texture)
		self.ring = texture
		record("ring", texture)
	end

	local ns = { Canvas = { PinMixin = {} }, Init = function() end }
	_G.Minimap = minimap
	_G.CreateFromMixins = function()
		return {}
	end
	assert(loadfile("UI/QuestBlob.lua"))("ShortestPathForever", ns)
	return minimap, ns
end

do
	local minimap, ns = fixture(true)
	ns.SetAreaBlob(true)
	equal(minimap.inside, BONUS.inside, "inside wears the gold set")
	equal(minimap.outside, BONUS.outside, "outside wears the gold set")
	equal(minimap.outsideSelected, BONUS.outsideSelected, "a super-tracked quest's selected edge wears the gold set")
	equal(minimap.ring, nil, "the minimap's own edge ring is not recoloured")

	ns.SetAreaBlob(false)
	equal(minimap.inside, QUEST.inside, "leaving hands the stock inside back")
	equal(minimap.outside, QUEST.outside, "leaving hands the stock outside back")
	equal(minimap.outsideSelected, QUEST.outsideSelected, "leaving hands the stock selected edge back")
	equal(minimap.ring, nil, "leaving leaves the edge ring as it was")

	local sets = #minimap.sets
	ns.SetAreaBlob(false)
	equal(#minimap.sets, sets, "repeated calls outside the area cost nothing")
end

do
	local minimap, ns = fixture(false)
	ns.SetAreaBlob(true)
	equal(minimap.inside, BONUS.inside, "a client without the selected setter still recolours the inside")
	equal(minimap.outside, BONUS.outside, "a client without the selected setter still recolours the outside")
	equal(minimap.outsideSelected, nil, "and it never calls a setter it does not have")
	equal(minimap.ring, nil, "a client without the selected setter still leaves the edge ring alone")
	ns.SetAreaBlob(false)
	equal(minimap.outside, QUEST.outside, "and hands the stock outside back")
end

print(("quest_blob_spec: %d checks: the minimap's gold area, not its edge ring, replaces the blue one"):format(checks))
