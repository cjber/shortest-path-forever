local addonName = ...
---@class SPFNamespace
local ns = select(2, ...)

-- The report window (cjber/adventure-guide-forever docs/report-window.md): `/path report` shows one block of text,
-- already selected, for the player to copy into a bug report. The text opens with what every Forever addon reports
-- (versions, build, locale, character, place), then the addon's own lines, the errors ns.SafeCall caught, and the
-- other addons loaded, cut to fit one message. This file knows nothing else about the addon: it copies across the
-- Forever addons with only its window title and hint changed. The field labels stay English in every locale; the
-- names and the addon's own lines are the client's.

local L, Art = ns.L, ns.Art
-- One Discord or forum message; a GitHub issue field takes it whole.
local LIMIT = 2000
-- The addon's own lines and the caught errors each stop here, leaving room for the header and the addon list.
local LINES_LIMIT, ERRORS_LIMIT = 1000, 600
local ICON = "Interface\\AddOns\\" .. addonName .. "\\media\\Icon"
local WIDTH, HEIGHT = 460, 380

---@class SPFReportModule
---@field Text fun(lines: string[]): string the whole report around the addon's `lines`, at most 2000 characters
---@field Show fun(text: string) show `text` in the report window, selected for copying
---@field Percent fun(value?: number): string a map coordinate as the map shows it
local Report = {}
ns.Report = Report

-- PortraitFrameTemplate's own members this file uses (Mainline/SharedUIPanelTemplates.xml).
---@class SPFReportWindow : Frame
---@field SetTitle fun(self: SPFReportWindow, title: string)
---@field GetPortrait fun(self: SPFReportWindow): Texture

---@type SPFReportWindow?
local window
---@type EditBox
local editBox
---@type string
local shown = ""

-- A map coordinate (0-1) as the map shows it, to one decimal; "-" when there is none.
---@param value? number
---@return string
local function Percent(value)
	return value and ("%.1f"):format(value * 100) or "-"
end
Report.Percent = Percent

-- The lines every Forever addon starts with.
---@return string[]
local function Header()
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "-"
	local gameVersion, build, _, interface = GetBuildInfo()
	local lines = {
		("%s %s | WoW %s (%s) %s | %s"):format(
			addonName,
			version,
			gameVersion,
			build,
			tostring(interface),
			GetLocale()
		),
	}
	local _, class = UnitClass("player")
	local _, race = UnitRace("player")
	lines[#lines + 1] = ("Character: level %d %s %s, %s"):format(
		UnitLevel("player") or 0,
		race or "-",
		class or "-",
		UnitFactionGroup("player") or "-"
	)
	local map = C_Map.GetBestMapForUnit("player")
	local point = map and C_Map.GetPlayerMapPosition(map, "player")
	local x, y
	if point then
		x, y = point:GetXY()
	end
	local info = map and C_Map.GetMapInfo(map)
	lines[#lines + 1] = ("Place: map %s (%s) %s, %s"):format(
		tostring(map or "-"),
		info and info.name or "-",
		Percent(x),
		Percent(y)
	)
	return lines
end

-- The errors ns.SafeCall caught this session, newest first.
---@return string[]
local function Errors()
	local caught = ns.CaughtErrors()
	if not caught[1] then
		return { "Errors: none caught" }
	end
	local lines = { ("Errors (%d):"):format(#caught) }
	for index = #caught, 1, -1 do
		local entry = caught[index]
		lines[#lines + 1] = ("- [%s] x%d %s"):format(entry.label, entry.count, entry.message)
		for line in entry.stack:gmatch("[^\n]+") do
			lines[#lines + 1] = "    " .. line
		end
	end
	return lines
end

-- The other loaded addons with their versions, as many as fit in `room` characters.
---@param room integer
---@return string
local function Addons(room)
	local names = {}
	for index = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(index)
		if name and name ~= addonName and C_AddOns.IsAddOnLoaded(index) then
			local version = C_AddOns.GetAddOnMetadata(name, "Version")
			names[#names + 1] = version and version ~= "" and (name .. " " .. version) or name
		end
	end
	table.sort(names)
	local text = ("Other addons (%d): "):format(#names)
	if not names[1] then
		return text .. "none"
	end
	for index, name in ipairs(names) do
		local more = index < #names and (" and %d more"):format(#names - index) or ""
		local piece = (index > 1 and ", " or "") .. name
		if #text + #piece + #more > room and index > 1 then
			return text .. (" and %d more"):format(#names - index + 1)
		end
		text = text .. piece
	end
	return text
end

-- The whole report: the header, the addon's `lines` (at most LINES_LIMIT characters), the caught errors (at most
-- ERRORS_LIMIT), then the other addons in what room is left. Each section has its own cap, so long addon lines never
-- push the errors out.
---@param lines string[]
---@return string
function Report.Text(lines)
	local text = table.concat({
		table.concat(Header(), "\n"),
		ns.CutText(table.concat(lines, "\n"), LINES_LIMIT),
		ns.CutText(table.concat(Errors(), "\n"), ERRORS_LIMIT),
	}, "\n")
	text = text .. "\n" .. Addons(math.max(LIMIT - #text - 1, 0))
	return ns.CutText(text, LIMIT)
end

---@param edit EditBox
local function Select(edit)
	edit:SetFocus()
	edit:HighlightText()
end

---@return SPFReportWindow
local function Window()
	if window then
		return window
	end
	local name = addonName .. "Report"
	local frame = CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate") --[[@as SPFReportWindow]]
	-- Escape closes it like any panel, with or without the edit box's focus (an addon-owned frame).
	table.insert(UISpecialFrames, name)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetTitle(L["Shortest Path report"])
	Art.Icon(frame:GetPortrait(), ICON, 62)

	local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	hint:SetPoint("TOPLEFT", 70, -32)
	hint:SetPoint("RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText(
		L["The text is selected. Press Ctrl+C (Cmd+C on a Mac) to copy it, then paste it into your bug report."]
	)

	local inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", 10, -64)
	inset:SetPoint("BOTTOMRIGHT", -10, 10)

	local scroll = CreateFrame("ScrollFrame", nil, inset, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject("ChatFontNormal")
	edit:SetWidth(WIDTH - 66)
	edit:SetMaxLetters(0)
	-- Read-only: typing puts the report back, still selected, so a stray key never changes what is copied.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(shown)
			Select(self)
		end
	end)
	edit:SetScript("OnEditFocusGained", edit.HighlightText)
	edit:SetScript("OnEscapePressed", function()
		frame:Hide()
	end)
	scroll:SetScrollChild(edit)
	editBox, window = edit, frame
	return frame
end

-- Show `text` in the window, all of it selected for Ctrl+C.
---@param text string
function Report.Show(text)
	local frame = Window()
	shown = text
	editBox:SetText(text)
	frame:Show()
	Select(editBox)
end
