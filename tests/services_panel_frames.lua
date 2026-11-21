-- Frame and font-string doubles for the headless Nearby panel specs.
local created, fontStrings = {}, {}

local function region()
	local r = { points = {}, shown = true }
	function r:SetPoint(...)
		self.points[#self.points + 1] = { ... }
	end
	function r:ClearAllPoints()
		self.points = {}
	end
	function r:SetText(text)
		self.text = text
	end
	function r:GetText()
		return self.text
	end
	function r.SetTextColor() end
	function r.SetJustifyH() end
	function r.SetWordWrap() end
	function r.SetMaxLines() end
	function r:SetAtlas(atlas)
		self.atlas = atlas
	end
	function r:SetTexture(file)
		self.file = file
	end
	function r:SetSize(width, height)
		self.width, self.height = width, height
	end
	function r.SetScale() end
	function r.SetBlendMode() end
	function r.SetAlpha() end
	function r:SetShown(shown)
		self.shown = shown
	end
	function r:Show()
		self.shown = true
	end
	function r:Hide()
		self.shown = false
	end
	function r:IsShown()
		return self.shown
	end
	function r.SetAllPoints() end
	function r.SetTexCoord() end
	return r
end

local function frame(frameType, name, parent, template)
	local f = {
		frameType = frameType,
		name = name,
		parent = parent,
		template = template,
		scripts = {},
		scriptHooks = {},
		setScriptCalls = {},
		hookScriptCalls = {},
		points = {},
		sized = template ~= nil,
		shown = true,
		width = 300,
		height = 40,
		events = {},
	}
	function f:SetScript(event, callback)
		self.scripts[event] = callback
		self.setScriptCalls[event] = (self.setScriptCalls[event] or 0) + 1
	end
	function f:HookScript(event, callback)
		self.scriptHooks[event] = self.scriptHooks[event] or {}
		self.scriptHooks[event][#self.scriptHooks[event] + 1] = callback
		self.hookScriptCalls[event] = (self.hookScriptCalls[event] or 0) + 1
	end
	function f:GetScript(event)
		return self.scripts[event]
	end
	function f:Show()
		self.shown = true
		if self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
		for _, handler in ipairs(self.scriptHooks.OnShow or {}) do
			handler(self)
		end
	end
	function f:Hide()
		self.shown = false
		if self.scripts.OnHide then
			self.scripts.OnHide(self)
		end
		for _, handler in ipairs(self.scriptHooks.OnHide or {}) do
			handler(self)
		end
	end
	function f:SetShown(shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end
	function f:IsShown()
		return self.shown
	end
	function f:SetPoint(...)
		self.points[#self.points + 1] = { ... }
	end
	function f:ClearAllPoints()
		self.points = {}
	end
	function f:SetSize(width, height)
		self.width, self.height, self.sized = width, height, true
	end
	function f:LockHighlight()
		self.highlightLocked = true
	end
	function f:UnlockHighlight()
		self.highlightLocked = false
	end
	function f:GetSize()
		return self.width, self.height
	end
	function f:SetWidth(width)
		self.width = width
	end
	function f:GetWidth()
		return self.width
	end
	function f:SetHeight(height)
		self.height, self.sized = height, true
	end
	function f:GetHeight()
		return self.height
	end
	function f:SetAllPoints()
		self.sized = true
	end
	function f:SetFrameLevel(level)
		self.level = level
	end
	function f.GetFrameLevel()
		return 1
	end
	function f:SetChecked(value)
		self.checked = value
	end
	function f:GetChecked()
		return self.checked
	end
	function f.EnableMouse() end
	function f:RegisterEvent(event)
		self.events[event] = true
	end
	function f.CreateTexture()
		return region()
	end
	function f.CreateFontString()
		local text = region()
		fontStrings[#fontStrings + 1] = text
		return text
	end
	if template == "SearchBoxTemplate" then
		f.Instructions = region()
		f.text = ""
		function f:SetText(text)
			self.text = text
			if self.scripts.OnTextChanged then
				self.scripts.OnTextChanged(self)
			end
			for _, handler in ipairs(self.scriptHooks.OnTextChanged or {}) do
				handler(self)
			end
		end
		function f:GetText()
			return self.text
		end
		function f.SetMaxLetters() end
	elseif template == "ScrollFrameTemplate" then
		f.ScrollBar = frame("Slider", nil, f)
		f.scroll = 0
		function f:SetScrollChild(child)
			self.child = child
		end
		function f:SetVerticalScroll(value)
			self.scroll = value
		end
		function f:GetVerticalScroll()
			return self.scroll
		end
	elseif template == "CollapseButtonTemplate" then
		function f:UpdateCollapsedState(collapsed)
			self.collapsed = collapsed
		end
	end
	created[#created + 1] = f
	return f
end

return frame, region, created, fontStrings
