---@meta

-- Kaliel's Tracker 8.11.1 (CurseForge !KalielsTracker) builds its quest right-click menus with the
-- MSA-DropDownMenu-1.0 library it ships (Libs/MSA-DropDownMenu-1.0), and tells addons each menu is open through its
-- CONTEXT_MENU_UPDATE signal. Core/KalielsTracker.lua reads these library globals only.

---@class SPFKalielsTrackerMenuInfo
---@field text? string
---@field isTitle? boolean a non-clickable heading
---@field notCheckable? boolean no check box and a shorter line
---@field isNotRadio? boolean
---@field func? fun(...)
---@field KTmenuExtended? boolean true once an addon has added its entries after the menu's own

---@type integer
MSA_DROPDOWNMENU_MENU_LEVEL = 1

---@return SPFKalielsTrackerMenuInfo
function MSA_DropDownMenu_CreateInfo() end

---@param info SPFKalielsTrackerMenuInfo
---@param level integer?
function MSA_DropDownMenu_AddButton(info, level) end

---@param level integer?
function MSA_DropDownMenu_AddSeparator(level) end
