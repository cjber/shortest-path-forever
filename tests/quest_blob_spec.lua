-- Run from the repository root: luajit tests/quest_blob_spec.lua
-- The minimap's quest area while the player stands in a held stop's area (#680): the inside and outside texture setters
-- repaint every watched quest, so they are never called. Only the super-tracked quest's selected edge may change, and
-- only when this client has that setter. A client without it leaves the minimap's stock blue alone, and Route.lua keeps
-- the stop's ring and line drawn there.
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local QUEST = {
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
	equal(ns.AreaBlobRecolours(), true, "a client with the selected-edge setter can recolour the minimap")
	ns.SetAreaBlob(true)
	equal(#minimap.sets, 1, "only one texture setter is called")
	equal(minimap.sets[1].name, "outsideSelected", "the super-tracked quest's selected edge")
	equal(minimap.outsideSelected, BONUS.outsideSelected, "and it wears the gold set")
	equal(minimap.inside, nil, "the shared inside texture is never set")
	equal(minimap.outside, nil, "the shared outside texture is never set")
	equal(minimap.ring, nil, "the minimap's own edge ring is not recoloured")

	ns.SetAreaBlob(false)
	equal(#minimap.sets, 2, "leaving calls the same one setter")
	equal(minimap.sets[2].name, "outsideSelected", "the selected edge again")
	equal(minimap.outsideSelected, QUEST.outsideSelected, "leaving hands the stock selected edge back")
	equal(minimap.inside, nil, "and still never touches the shared inside texture")
	equal(minimap.outside, nil, "nor the shared outside texture")
	equal(minimap.ring, nil, "leaving leaves the edge ring as it was")

	local sets = #minimap.sets
	ns.SetAreaBlob(false)
	equal(#minimap.sets, sets, "repeated calls outside the area cost nothing")
end

do
	local minimap, ns = fixture(false)
	equal(ns.AreaBlobRecolours(), false, "a client without the selected-edge setter cannot recolour the minimap")
	ns.SetAreaBlob(true)
	equal(#minimap.sets, 0, "no minimap texture setter is called without the selected-edge setter")
	equal(minimap.inside, nil, "the shared inside texture stays as it was")
	equal(minimap.outside, nil, "the shared outside texture stays as it was")
	equal(minimap.outsideSelected, nil, "and there is no selected edge to set")
	equal(minimap.ring, nil, "the edge ring stays as it was")
	ns.SetAreaBlob(false)
	equal(#minimap.sets, 0, "leaving calls nothing either, so the stock blue stays")
end

print(("quest_blob_spec: %d checks: only the tracked quest's edge may turn gold"):format(checks))
