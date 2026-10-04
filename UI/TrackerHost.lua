---@type string, ForeverTrackerNamespace
local _, ns = ...

---@class ForeverTrackerModule : Frame
---@field parentContainer? Frame
---@field SetContainer fun(self: ForeverTrackerModule, container: Frame)

---@class ForeverTrackerHostAPI
---@field Attach fun(module: Frame)
---@field IsAttached fun(module: Frame?): boolean
---@field Debug fun(): string the tracker stack's anchors, heights and in-combat state, for /agf tracker

---@class ForeverNativeTrackerHeader : Frame
---@field Text FontString
---@field MinimizeButton Button

---@class ForeverNativeTrackerFrame : Frame
---@field Header ForeverNativeTrackerHeader
---@field NineSlice Frame?
---@field isCollapsed? boolean

-- Sharing the native tracker collection also shares its Edit Mode execution path.
-- Keep our sections and their frame pools entirely outside that collection.
if not ObjectiveTrackerFrame then
	return
end

if ForeverTrackerHost then
	ns.TrackerHost = ForeverTrackerHost
	return
end

local host = CreateFrame("Frame", "ForeverTrackerCompanion", UIParent)
---@class ForeverTrackerHostAPI
local api = {}
local fallbackSettings = { attached = true }
local function Coordinate(value)
	if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
end
---@return ForeverTrackerSettings
local function Settings()
	local settings = ns.TrackerHostSettings and ns.TrackerHostSettings() or fallbackSettings
	if type(settings.attached) ~= "boolean" then
		settings.attached = true
	end
	settings.x, settings.y = Coordinate(settings.x), Coordinate(settings.y)
	return settings
end
local attached
local dragging = false
local attachmentCallbacks = {}
-- Preserve Blizzard's edit-mode placement for the combined column. The
-- private host takes the native frame's original slot; the native frame is
-- placed below it after the private content has laid out. This keeps every
-- section in one column without registering our frames with Blizzard's
-- secure module collection.
local nativeAnchor
local appliedNativeAnchor
-- Whether the native frame was clamped to the screen before we stacked it below our column.
local nativeClamped

-- Hands the native frame's screen clamp back whenever it stops being stacked under our column.
local function RestoreNativeClamp()
	if nativeClamped then
		ObjectiveTrackerFrame:SetClampedToScreen(true)
	end
	nativeClamped = nil
end
local function IsAppliedNativeAnchor(point, relativeTo, relativePoint, x, y)
	return appliedNativeAnchor
		and appliedNativeAnchor.point == point
		and appliedNativeAnchor.relativeTo == relativeTo
		and appliedNativeAnchor.relativePoint == relativePoint
		and math.abs(appliedNativeAnchor.x - (x or 0)) <= 0.5
		and math.abs(appliedNativeAnchor.y - (y or 0)) <= 0.5
end
local function StackPoints(point)
	if point == "CENTER" or point == "TOP" or point == "BOTTOM" then
		return "TOP", "BOTTOM"
	end
	local horizontal = point:find("RIGHT", 1, true) and "RIGHT" or "LEFT"
	return "TOP" .. horizontal, "BOTTOM" .. horizontal
end
local function CaptureNativeAnchor()
	local point, relativeTo, relativePoint, x, y = ObjectiveTrackerFrame:GetPoint()
	if nativeAnchor and (relativeTo == host or IsAppliedNativeAnchor(point, relativeTo, relativePoint, x, y)) then
		return
	end
	nativeAnchor = {
		point = point or "TOPRIGHT",
		relativeTo = relativeTo or UIParent,
		relativePoint = relativePoint or "TOPRIGHT",
		x = x or 0,
		y = y or 0,
	}
end
host:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
local function MatchNativeScale()
	local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
	local nativeScale = ObjectiveTrackerFrame.GetEffectiveScale and ObjectiveTrackerFrame:GetEffectiveScale()
	if parentScale and nativeScale and parentScale > 0 then
		host:SetScale(nativeScale / parentScale)
	end
end
MatchNativeScale()
host:SetWidth(ObjectiveTrackerFrame:GetWidth())
host:SetHeight(1)
host:SetMovable(true)
host:SetClampedToScreen(true)
local grip = CreateFrame("Button", nil, host)
grip:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
grip:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
grip:SetHeight(24)
grip:RegisterForDrag("LeftButton")
local label = grip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("CENTER", grip, "CENTER", 0, 0)
local dragTitle = rawget(ns.L, "TRACKER_DRAG_TITLE") or ns.L["Forever tracker"]
local dragTooltip = rawget(ns.L, "TRACKER_DRAG_TOOLTIP") or ns.L["Drag to move"]
label:SetText(dragTitle)
grip:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(dragTooltip)
	GameTooltip:Show()
end)
grip:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)
grip:SetScript("OnDragStart", function()
	if attached or InCombatLockdown() then
		return
	end
	dragging = true
	host:StartMoving()
end)
grip:SetScript("OnDragStop", function()
	if not dragging then
		return
	end
	dragging = false
	host:StopMovingOrSizing()
	local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
	api.SavePosition((host:GetLeft() or 0) * scale, (host:GetTop() or 0) * scale - UIParent:GetHeight())
end)
grip:Hide()
local modules, queued, ready = {}, false, false
local requestedNativeHeight
local appliedNativeHeight
local pools = CreateFramePoolCollection()

local function NotifyAttachment(value)
	for _, callback in ipairs(attachmentCallbacks) do
		callback(value)
	end
end

local function Acquire(parent, template)
	local info = C_XMLUtil.GetTemplateInfo(template)
	local pool = pools:GetOrCreatePool(info and info.type or "Frame", parent, template)
	---@class ForeverTrackerPooledFrame : Frame
	---@field GetLine? function
	---@field FreeLine? function
	---@field OnAnimFinished? function
	local frame, isNew = pool:Acquire(template)
	frame.template = template
	return frame, isNew
end

local function GetLine(block, key, template)
	template = template or block.parentModule.lineTemplate
	local line = block:GetExistingLine(key)
	if line and line.template ~= template then
		block:FreeLine(line)
		line = nil
	end
	if not line then
		line = Acquire(block, template)
		line:SetParent(block)
		line:Show()
	end
	block.usedLines[key] = line
	line.objectiveKey, line.parentBlock, line.used = key, block, true
	return line
end

local function FreeLine(block, line)
	block.usedLines[line.objectiveKey] = nil
	pools:Release(line)
	line:Hide()
	if line.OnFree then
		line:OnFree(block)
	end
end

local function FreeResources(resources, onFree)
	for key, frame in pairs(resources or {}) do
		if not frame.used then
			resources[key] = nil
			if onFree and frame.OnFree then
				frame:OnFree()
			end
			pools:Release(frame)
		end
	end
end

-- Our blocks have no native reward toasts; their animations stay in the private cache.
local function OnAnimFinished(block)
	if block.activeAnim ~= block.AddAnim then
		block.parentModule:RemoveBlockFromCache(block)
		block.parentModule:MarkDirty()
		block:SetAlpha(0)
	end
	block.activeAnim = nil
	if block.pendingAnim then
		local anim = block.pendingAnim
		block.pendingAnim = nil
		block:TryPlayAnim(anim)
	end
end

local Module = {}
function Module:AcquireFrame(template)
	local frame, isNew = Acquire(self, template)
	frame:SetParent(self.ContentsFrame)
	if frame.GetLine then
		frame.GetLine, frame.FreeLine = GetLine, FreeLine
		if frame.OnAnimFinished then
			frame.OnAnimFinished = OnAnimFinished
		end
	end
	return frame, isNew
end
function Module:FreeBlock(block)
	self:RemoveBlockFromCache(block, true)
	block:Free()
	self.usedBlocks[block.template][block.id] = nil
	pools:Release(block)
	self:OnFreeBlock(block)
end
function Module:FreeUnusedTimerBars()
	FreeResources(self.usedTimerBars)
end
function Module:FreeUnusedProgressBars()
	FreeResources(self.usedProgressBars, true)
end
function Module:FreeUnusedRightEdgeFrames()
	FreeResources(self.usedRightEdgeFrames)
end
function Module.GetContextMenuParent(_)
	return host
end

local function OverlapsMinimap()
	local minimap = _G.Minimap
	if not minimap or not minimap.IsShown or not minimap:IsShown() then
		return false
	end
	local left, right, top, bottom = host:GetLeft(), host:GetRight(), host:GetTop(), host:GetBottom()
	local ml, mr, mt, mb = minimap:GetLeft(), minimap:GetRight(), minimap:GetTop(), minimap:GetBottom()
	local hostScale = host.GetEffectiveScale and host:GetEffectiveScale() or 1
	local mapScale = minimap.GetEffectiveScale and minimap:GetEffectiveScale() or 1
	local screen = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
	if not (left and right and top and bottom and ml and mr and mt and mb) then
		return false
	end
	left, right, top, bottom =
		left * hostScale / screen, right * hostScale / screen, top * hostScale / screen, bottom * hostScale / screen
	ml, mr, mt, mb = ml * mapScale / screen, mr * mapScale / screen, mt * mapScale / screen, mb * mapScale / screen
	return left < mr and right > ml and bottom < mt and top > mb
end

local function AvoidMinimap(point)
	if not OverlapsMinimap() then
		return
	end
	host:ClearAllPoints()
	-- Blizzard can temporarily leave the protected frame anchored to our host. Never
	-- anchor back to it in that state: use the saved Edit Mode slot to avoid a cycle.
	local _, relativeTo = ObjectiveTrackerFrame:GetPoint()
	if relativeTo == host and nativeAnchor then
		local direction = point:find("RIGHT", 1, true) and -1 or 1
		host:SetPoint(
			nativeAnchor.point,
			nativeAnchor.relativeTo,
			nativeAnchor.relativePoint,
			nativeAnchor.x + direction * (host:GetWidth() + 8),
			nativeAnchor.y
		)
	elseif point:find("LEFT", 1, true) then
		host:SetPoint("TOPLEFT", ObjectiveTrackerFrame, "TOPRIGHT", 0, 0)
	else
		host:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "TOPLEFT", 0, 0)
	end
end

local function SidePoint(point)
	local left, right = ObjectiveTrackerFrame:GetLeft(), ObjectiveTrackerFrame:GetRight()
	local screen = UIParent:GetWidth()
	local nativeScale = ObjectiveTrackerFrame.GetEffectiveScale and ObjectiveTrackerFrame:GetEffectiveScale() or 1
	local screenScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
	if left and right and screen and nativeScale > 0 and screenScale > 0 then
		local nativeCenter = (left + right) * nativeScale / (2 * screenScale)
		return nativeCenter <= screen / 2 and "LEFT" or "RIGHT"
	end
	return point:find("LEFT", 1, true) and "LEFT" or "RIGHT"
end

-- Where a detached column sits until the player drags it: beside the native tracker and level with its top, so
-- neither draws over the other. To its left when the column fits there, otherwise to its right. Offsets are from
-- UIParent's top left corner in the host's own scale; the caller keeps them on screen.
local function BesideNative(width, screenHeight)
	local left, right, top =
		ObjectiveTrackerFrame:GetLeft(), ObjectiveTrackerFrame:GetRight(), ObjectiveTrackerFrame:GetTop()
	if not (left and right and top) then
		return 0, -40
	end
	local toHost = ObjectiveTrackerFrame:GetEffectiveScale() / host:GetEffectiveScale()
	local x = left * toHost - 8 - width
	if x < 0 then
		x = right * toHost + 8
	end
	return x, top * toHost - screenHeight
end

-- The native "All Objectives" header sits at the top of the shared column. Blizzard's trackers re-anchor it to
-- the native frame at the end of every update (ObjectiveTrackerFrameMixin:UpdateHeaderPosition), so our anchor is
-- re-applied right after with a secure post-hook. Only SetPoint and ClearAllPoints are called on the unprotected
-- header; no field on a Blizzard frame or table is written, and the protected native frame is never moved in
-- combat.
local HEADER_TOP_PADDING = 38
local nativeHeader = ObjectiveTrackerFrame.Header --[[@as ForeverNativeTrackerHeader?]]
local headerAdopted = false
---@type { point: string, relativeTo: ScriptRegion, relativePoint: string, x: number, y: number }?
local nativeHeaderAnchor

local function NativeHeaderShown()
	return nativeHeader ~= nil and nativeHeader:IsShown() and ObjectiveTrackerFrame:IsShown()
end

local function NativeCollapsed()
	return ObjectiveTrackerFrame.isCollapsed == true
end

local function CaptureNativeHeaderAnchor()
	if nativeHeaderAnchor or not nativeHeader then
		return
	end
	local point, relativeTo, relativePoint, x, y = nativeHeader:GetPoint()
	nativeHeaderAnchor = {
		point = point or "TOPLEFT",
		relativeTo = relativeTo or ObjectiveTrackerFrame,
		relativePoint = relativePoint or "TOPLEFT",
		x = x or 0,
		y = y or 0,
	}
end

local function AdoptNativeHeader()
	if not nativeHeader then
		return
	end
	if not headerAdopted then
		CaptureNativeHeaderAnchor()
		headerAdopted = true
	end
	nativeHeader:ClearAllPoints()
	nativeHeader:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
end

local function RestoreNativeHeader()
	if not headerAdopted or not nativeHeader then
		return
	end
	local anchor = nativeHeaderAnchor
	if not anchor then
		return
	end
	nativeHeader:ClearAllPoints()
	nativeHeader:SetPoint(anchor.point, anchor.relativeTo, anchor.relativePoint, anchor.x, anchor.y)
	headerAdopted = false
end

-- Blizzard's trackers put their own header anchor back at the end of every update, after any content that changed
-- it, so ours is re-applied right after. The same update restores the native frame's own anchor through the
-- managed frame containers, so the host is marked dirty too: the frame came back to the saved slot and only a
-- fresh reflow restacks it below the column. This is a secure post-hook: it moves the unprotected header only and
-- reads no Blizzard state, so the protected tracker's Edit Mode and combat paths stay clean.
local function OnNativeLayout()
	if headerAdopted then
		AdoptNativeHeader()
	end
	if host.MarkDirty then
		host:MarkDirty()
	end
end
hooksecurefunc(ObjectiveTrackerFrame, "UpdateHeaderPosition", OnNativeLayout) -- taint-ok: unprotected header
-- The managed frame containers re-anchor the native frame from their own Layout and then report the new height;
-- no header update follows that path, so it marks the host dirty on its own.
hooksecurefunc(ObjectiveTrackerFrame, "UpdateHeight", OnNativeLayout) -- taint-ok: unprotected header

-- Lays every section out from the host's top, leaving `reserve` pixels for the native header. Returns whether any
-- section drew, which decides if the header moves and the native frame leaves its title room.
local function LayoutModules(width, available, reserve)
	table.sort(modules, function(a, b)
		return a.uiOrder < b.uiOrder
	end)
	local heights, total = {}, 0
	for index, module in ipairs(modules) do
		module:SetWidth(width)
		module:Update(math.max(0, available - total))
		local used = module:GetContentsHeight()
		heights[index] = used
		if used > 0 then
			total = total + used + 10
		end
	end
	local hasSections = total > 0
	local height = hasSections and reserve or 0
	for index, module in ipairs(modules) do
		module:ClearAllPoints()
		module:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -height)
		local used = heights[index]
		if used > 0 then
			height = height + used + 10
		end
	end
	host:SetHeight(math.max(1, height))
	return hasSections
end
local function Layout()
	queued = false
	local settings = Settings()
	local desired = settings.attached ~= false
	if attached == nil then
		attached = desired
	elseif not InCombatLockdown() and desired ~= attached then
		if not desired then
			local currentPoint, currentRelative, currentRelativePoint, currentX, currentY =
				ObjectiveTrackerFrame:GetPoint()
			if
				nativeAnchor
				and (
					currentRelative == host
					or IsAppliedNativeAnchor(currentPoint, currentRelative, currentRelativePoint, currentX, currentY)
				)
			then
				ObjectiveTrackerFrame:ClearAllPoints()
				ObjectiveTrackerFrame:SetPoint(
					nativeAnchor.point,
					nativeAnchor.relativeTo,
					nativeAnchor.relativePoint,
					nativeAnchor.x,
					nativeAnchor.y
				)
				appliedNativeAnchor = nil
			end
			if appliedNativeHeight and requestedNativeHeight then
				local current = ObjectiveTrackerFrame:GetHeight()
				if math.abs(current - appliedNativeHeight) <= 0.5 then
					ObjectiveTrackerFrame:SetHeight(requestedNativeHeight)
				end
			end
			appliedNativeHeight = nil
			RestoreNativeClamp()
		end
		attached = desired
	end
	grip:SetShown(not attached)
	if not attached then
		RestoreNativeHeader()
		host:Show()
		MatchNativeScale()
		local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local screenWidth, screenHeight = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
		local width = math.min(ObjectiveTrackerFrame:GetWidth(), screenWidth)
		host:SetWidth(width)
		if dragging then
			return
		end
		local x, y
		if settings.x and settings.y then
			x, y = settings.x / scale, settings.y / scale
		else
			x, y = BesideNative(width, screenHeight)
		end
		x = math.max(0, math.min(x, math.max(0, screenWidth - width)))
		y = math.min(0, math.max(y, 24 - screenHeight))
		host:ClearAllPoints()
		host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
		LayoutModules(width, math.max(24, screenHeight + y - 24), 24)
		y = math.min(0, math.max(y, math.min(host:GetHeight(), screenHeight) - screenHeight))
		host:ClearAllPoints()
		host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
		return
	end
	if InCombatLockdown() and attached then
		-- The native tracker is protected: in combat it cannot be restacked below our column. The header is not
		-- protected and nothing protected anchors to it, so it stays at the top of our column. Only Blizzard moving
		-- the native frame itself sends us to the one-column fallback below its content.
		if appliedNativeAnchor and IsAppliedNativeAnchor(ObjectiveTrackerFrame:GetPoint()) then
			-- Still stacked where the last reflow left both frames: nothing to move.
			return
		end
		CaptureNativeAnchor()
		host:SetWidth(ObjectiveTrackerFrame:GetWidth())
		host:ClearAllPoints()
		-- Once Blizzard has restored the protected frame to its saved slot, anchor our private
		-- column to the native frame's actual top edge. This follows CENTER/BOTTOM anchors,
		-- offsets and UI scale without writing the protected frame. During the brief window
		-- before that restore, the native frame still points at us; use the saved slot instead
		-- to avoid creating an anchor cycle.
		local point, nativeRelativeTo = ObjectiveTrackerFrame:GetPoint()
		if nativeRelativeTo == host then
			-- Preserve the saved slot if a legacy host-relative anchor is restored.
			-- Moving relative to that protected child would create an anchor cycle.
			if nativeAnchor then
				host:SetPoint(
					nativeAnchor.point,
					nativeAnchor.relativeTo,
					nativeAnchor.relativePoint,
					nativeAnchor.x,
					nativeAnchor.y
				)
			end
		elseif point then
			local nativePoint, hostPoint = StackPoints(point)
			-- First choice: one column. The header goes back to the native frame and our sections sit directly below
			-- the native tracker's visible content, measured from its own content region, so the column reads the
			-- header, the game's modules, then the Forever sections. The protected frame stays where Blizzard put it.
			local nineSlice = ObjectiveTrackerFrame.NineSlice
			local nativeBottom = ObjectiveTrackerFrame:GetBottom()
			local contentBottom = nineSlice and ObjectiveTrackerFrame:IsShown() and nineSlice:GetBottom()
				or nativeBottom
			local contentGap = (nativeBottom and contentBottom) and (contentBottom - nativeBottom) or 0
			RestoreNativeHeader()
			host:SetPoint("TOP", ObjectiveTrackerFrame, "BOTTOM", 0, contentGap)
			local layoutScale = host.GetEffectiveScale and host:GetEffectiveScale() or 1
			local layoutScreenScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or layoutScale
			local layoutMargin = 24 * layoutScreenScale / layoutScale
			contentBottom = contentBottom or 0
			LayoutModules(host:GetWidth(), math.max(0, contentBottom - layoutMargin), 0)
			if contentBottom - (host:GetHeight() or 0) >= layoutMargin then
				return
			end
			-- The one-column placement would run off the bottom of the screen. If there is no room above the restored
			-- tracker, use the side away from its anchored edge. This keeps the private column visible without moving
			-- or overlapping the protected frame.
			host:ClearAllPoints()
			local nativeTop = ObjectiveTrackerFrame:GetTop() or 0
			local screenTop = UIParent:GetHeight() or nativeTop
			local hostScale = host.GetEffectiveScale and host:GetEffectiveScale() or 1
			local screenScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
			local nativeScale = ObjectiveTrackerFrame.GetEffectiveScale and ObjectiveTrackerFrame:GetEffectiveScale()
				or 1
			local room = screenTop * screenScale - nativeTop * nativeScale
			if room >= math.max(host:GetHeight() or 0, 1) * hostScale then
				host:SetPoint(hostPoint, ObjectiveTrackerFrame, nativePoint, 0, 0)
			elseif SidePoint(point) == "LEFT" then
				host:SetPoint("TOPLEFT", ObjectiveTrackerFrame, "TOPRIGHT", 0, 0)
			else
				host:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "TOPLEFT", 0, 0)
			end
			AvoidMinimap(point)
		elseif nativeAnchor then
			local _, hostPoint = StackPoints(nativeAnchor.point)
			host:SetPoint(
				hostPoint,
				nativeAnchor.relativeTo,
				nativeAnchor.relativePoint,
				nativeAnchor.x,
				nativeAnchor.y
			)
		end
		AvoidMinimap(nativeAnchor and nativeAnchor.point or "TOPRIGHT")
		return
	end
	-- Read the global each time, not once at load: Blizzard_EditMode is load-on-demand, so it may appear later.
	if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
		RestoreNativeHeader()
		return
	end
	table.sort(modules, function(a, b)
		return a.uiOrder < b.uiOrder
	end)
	-- The native frame may only receive its final Edit Mode anchor after the
	-- player and saved variables are ready. Capture it before our first reflow.
	CaptureNativeAnchor()
	if not requestedNativeHeight and (ObjectiveTrackerFrame:GetHeight() or 0) > 0 then
		requestedNativeHeight = ObjectiveTrackerFrame:GetHeight()
	end
	local width = ObjectiveTrackerFrame:GetWidth()
	MatchNativeScale()
	host:ClearAllPoints()
	host:SetPoint(
		nativeAnchor.point,
		nativeAnchor.relativeTo,
		nativeAnchor.relativePoint,
		nativeAnchor.x,
		nativeAnchor.y
	)
	local layoutScale = host.GetEffectiveScale and host:GetEffectiveScale() or 1
	local layoutScreenScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or layoutScale
	local layoutMargin = 40 * layoutScreenScale / layoutScale
	local available = math.max(0, (host:GetTop() or UIParent:GetHeight()) - layoutMargin)
	host:SetWidth(width)
	-- The native "All Objectives" header rides at the top of the shared column whenever both it and a section are
	-- shown, so its title stays above the Forever rows. A hidden or collapsed header leaves the host as it was,
	-- with no reserved gap.
	local collapsed = NativeCollapsed()
	local headerCandidate = not collapsed and NativeHeaderShown()
	local hasSections = false
	if collapsed then
		RestoreNativeHeader()
		host:SetHeight(1)
		host:Hide()
	else
		host:Show()
		local reserve = headerCandidate and HEADER_TOP_PADDING or 0
		hasSections = LayoutModules(width, math.max(0, available - reserve), reserve)
		if hasSections and headerCandidate then
			AdoptNativeHeader()
		else
			RestoreNativeHeader()
		end
	end
	local headerReserve = hasSections and headerCandidate and HEADER_TOP_PADDING or 0
	-- If the combined column would run below the screen, move the whole
	-- column upward from its saved edit-mode slot.  The offset is calculated
	-- from the original point each pass, so repeated refreshes never drift.
	local shift = 0
	host:ClearAllPoints()
	host:SetPoint(
		nativeAnchor.point,
		nativeAnchor.relativeTo,
		nativeAnchor.relativePoint,
		nativeAnchor.x,
		nativeAnchor.y
	)
	local screenHeight = UIParent:GetHeight()
	local top = host:GetTop()
	local scale = host.GetEffectiveScale and host:GetEffectiveScale() or 1
	local screenScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or scale
	local margin = 24 * screenScale / scale
	local screen = screenHeight and screenHeight * screenScale / scale
	if screen and top and top - host:GetHeight() < margin then
		shift = margin - (top - host:GetHeight())
		shift = math.min(shift, math.max(0, screen - margin - top))
	end
	host:ClearAllPoints()
	host:SetPoint(
		nativeAnchor.point,
		nativeAnchor.relativeTo,
		nativeAnchor.relativePoint,
		nativeAnchor.x,
		nativeAnchor.y + shift
	)
	local nativeScale = ObjectiveTrackerFrame.GetEffectiveScale and ObjectiveTrackerFrame:GetEffectiveScale() or 1
	local hostScale = host.GetEffectiveScale and host:GetEffectiveScale() or 1
	local hostLeft = (host:GetLeft() or 0) * hostScale / screenScale
	-- The header no longer sits inside the native frame's slot, so the frame moves up by exactly the room its
	-- title used to take; its first module then starts where the private host ends.
	local nativeY = ((host:GetBottom() or 0) + headerReserve) * hostScale / screenScale - UIParent:GetHeight()
	-- Blizzard restores the native frame's own height whenever it updates, and in combat we cannot shorten it
	-- again. Clamped to the screen, the taller frame would be pushed up over our column; unclamped it only runs
	-- off the bottom edge until combat ends.
	if ObjectiveTrackerFrame.IsClampedToScreen then
		if nativeClamped == nil then
			nativeClamped = ObjectiveTrackerFrame:IsClampedToScreen() and true or false
		end
		ObjectiveTrackerFrame:SetClampedToScreen(false)
	end
	ObjectiveTrackerFrame:ClearAllPoints()
	local nativeX = hostLeft * screenScale / nativeScale
	local nativeOffsetY = nativeY * screenScale / nativeScale
	ObjectiveTrackerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", nativeX, nativeOffsetY)
	appliedNativeAnchor = {
		point = "TOPLEFT",
		relativeTo = UIParent,
		relativePoint = "TOPLEFT",
		x = nativeX,
		y = nativeOffsetY,
	}
	local currentNativeHeight = ObjectiveTrackerFrame:GetHeight() or requestedNativeHeight
	if
		(appliedNativeHeight and math.abs(currentNativeHeight - appliedNativeHeight) > 0.5)
		or (
			not appliedNativeHeight
			and requestedNativeHeight
			and math.abs(currentNativeHeight - requestedNativeHeight) > 0.5
		)
	then
		requestedNativeHeight = currentNativeHeight
	end
	local bottom = host.GetBottom and host:GetBottom() or ((host:GetTop() or 0) - host:GetHeight())
	local remaining = math.max(1, bottom + headerReserve - margin)
	local nativeHeight = math.min(requestedNativeHeight or remaining, remaining)
	if math.abs(currentNativeHeight - nativeHeight) > 0.5 then
		ObjectiveTrackerFrame:SetHeight(nativeHeight)
		appliedNativeHeight = nativeHeight
	end
end

function host.MarkDirty(_)
	if ready and not queued then
		queued = true
		C_Timer.After(0, Layout)
	end
end
function host.IsCollapsed(_)
	return attached == true and NativeCollapsed()
end
function host:ForceExpand()
	self:MarkDirty()
end

function api.GetSettings()
	return Settings()
end
function api.IsAttachedToQuestTracker()
	return Settings().attached ~= false
end
function api.SetAttached(value)
	value = not not value
	local settings = Settings()
	if settings.attached == value then
		return
	end
	settings.attached = value
	NotifyAttachment(value)
	host:MarkDirty()
end
function api.OnAttachmentChanged(callback)
	attachmentCallbacks[#attachmentCallbacks + 1] = callback
end
function api.SavePosition(x, y)
	if attached or type(x) ~= "number" or type(y) ~= "number" then
		return
	end
	local settings = Settings()
	settings.x, settings.y = x, y
	host:MarkDirty()
end
function api.Attach(module)
	---@cast module ForeverTrackerModule
	if module.parentContainer == host then
		return
	end
	Mixin(module, Module)
	modules[#modules + 1] = module
	module:SetContainer(host)
	host:MarkDirty()
end
function api.IsAttached(module)
	---@cast module ForeverTrackerModule?
	return module ~= nil and module.parentContainer == host
end
host:RegisterEvent("PLAYER_REGEN_ENABLED")
host:RegisterEvent("PLAYER_REGEN_DISABLED")
host:RegisterEvent("DISPLAY_SIZE_CHANGED")
host:RegisterEvent("UI_SCALE_CHANGED")
host:SetScript("OnEvent", function()
	host:MarkDirty()
end)
ObjectiveTrackerFrame:HookScript("OnSizeChanged", function()
	host:MarkDirty()
end)
-- Collapsing "All Objectives" hides the shared sections too. Mark the host dirty on the click that flips it; the
-- native collapse method itself stays unhooked and untouched, and the native header keeps its parent so its button
-- resolves the native container normally.
if nativeHeader and nativeHeader.MinimizeButton then
	nativeHeader.MinimizeButton:HookScript("OnClick", function()
		host:MarkDirty()
	end)
end
-- Edit Mode restores Blizzard's saved anchor through its public callbacks. Reflow
-- on those events instead of polling the native frame every frame.
if EventRegistry and EventRegistry.RegisterCallback then
	local function OnEditModeChanged()
		local editing = EditModeManagerFrame
			and EditModeManagerFrame.IsEditModeActive
			and EditModeManagerFrame:IsEditModeActive()
		if editing and attached then
			-- Edit Mode drags the native frame itself, so it needs its own edge-of-screen clamp back.
			RestoreNativeClamp()
			host:Hide()
		else
			host:Show()
		end
		host:MarkDirty()
	end
	EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeChanged, host)
	EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeChanged, host)
	EventRegistry:RegisterCallback("EditMode.SavedLayouts", OnEditModeChanged, host)
end
-- A developer diagnostic for the tracker stack (/agf tracker). The combat overlap is otherwise invisible headlessly: it
-- prints both frames' anchors, heights and who each is anchored to.
---@return string
function api.Debug()
	-- Raw literals on purpose: this host is shared with the companion addons, whose ns.L has no AGF keys, and
	-- lint_copy only rejects literals passed straight to Print/SetText (this returns a string instead).
	local function point(frame)
		local p = { frame:GetPoint() }
		local relative = p[2] == host and "host" or tostring(p[2])
		return ("%s rel %s %s %.1f,%.1f"):format(
			tostring(p[1]),
			relative,
			tostring(p[3]),
			tonumber(p[4]) or 0,
			tonumber(p[5]) or 0
		)
	end
	local function geometry(frame)
		return ("%.1f,%.1f-%.1f,%.1f s%.2f"):format(
			frame:GetLeft() or -1,
			frame:GetTop() or -1,
			frame:GetRight() or -1,
			frame:GetBottom() or -1,
			frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
		)
	end
	local form = "combat=%s shown=%s hostH=%.1f host[%s] g[%s] nativeH=%.1f native[%s] g[%s] uiS%.2f"
	return (form .. " stacked=%s clamped=%s"):format(
		tostring(InCombatLockdown()),
		tostring(host:IsShown()),
		host:GetHeight() or -1,
		point(host),
		geometry(host),
		ObjectiveTrackerFrame:GetHeight() or -1,
		point(ObjectiveTrackerFrame),
		geometry(ObjectiveTrackerFrame),
		UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1,
		tostring(IsAppliedNativeAnchor(ObjectiveTrackerFrame:GetPoint()) and true or false),
		tostring(ObjectiveTrackerFrame.IsClampedToScreen and ObjectiveTrackerFrame:IsClampedToScreen())
	)
end

ForeverTrackerHost = api -- taint-ok: addon-owned companion tracker registry
ns.TrackerHost = api

EventUtil.ContinueAfterAllEvents(function()
	ready = true
	host:MarkDirty()
end, "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED")
