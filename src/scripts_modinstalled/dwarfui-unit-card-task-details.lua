--@ module=true

-- Unit-card overlay for active task-destination details.

local overlay = require('plugins.overlay')
local task_details = reqscript('dwarfui/unit_card_task')

---@class dwarfui.UnitCardTaskDetailsOverlay: plugins.overlay.OverlayWidget
UnitCardTaskDetailsOverlay = defclass(UnitCardTaskDetailsOverlay,
    overlay.OverlayWidget)
UnitCardTaskDetailsOverlay.ATTRS{
    desc='Shows the destination for an active hauling task on the unit overview.',
    default_enabled=true,
    default_pos={x=1, y=1},
    viewscreens='dwarfmode/ViewSheets/UNIT/Overview',
    fullscreen=true,
    frame={l=0, t=0, w=1, h=1},
}

-- The third left-hand Overview panel reserves this cell below its task row.
local TASK_DESTINATION_X = 167
local TASK_ACTION_Y = 31
local TASK_DESTINATION_Y = 32
local TASK_PANEL_WIDTH = 29

---Returns whether the pointer is inside one task-detail row's native panel.
---@param mouse_x integer|nil
---@param mouse_y integer|nil
---@param row_y integer
---@return boolean
local function is_pointer_over_task_row(mouse_x, mouse_y, row_y)
    return mouse_x ~= nil and mouse_y == row_y and
        mouse_x >= TASK_DESTINATION_X and
        mouse_x < TASK_DESTINATION_X + TASK_PANEL_WIDTH
end

---Selects full or capped task text according to the pointer position.
---@param text string|nil
---@param mouse_x integer|nil
---@param mouse_y integer|nil
---@param row_y integer
---@return string|nil
local function resolve_row_text(text, mouse_x, mouse_y, row_y)
    if not text then return end
    if task_details.is_panel_text_truncated(text, TASK_PANEL_WIDTH) and
            is_pointer_over_task_row(mouse_x, mouse_y, row_y) then
        return text
    end
    return task_details.truncate_panel_text(text, TASK_PANEL_WIDTH)
end

---Paints active haul pickup and destination details in the third Overview panel.
---@param dc gui.Painter
function UnitCardTaskDetailsOverlay:render(dc)
    UnitCardTaskDetailsOverlay.super.render(self, dc)
    local unit = dfhack.gui.getSelectedUnit(true)
    local mouse_x, mouse_y = dfhack.screen.getMousePos()
    local grab_text = resolve_row_text(task_details.get_grab_item_text(unit),
        mouse_x, mouse_y, TASK_ACTION_Y)
    local text = resolve_row_text(task_details.get_haul_destination_text(unit),
        mouse_x, mouse_y, TASK_DESTINATION_Y)
    if grab_text then
        dc:seek(TASK_DESTINATION_X, TASK_ACTION_Y):string(grab_text,
            COLOR_YELLOW)
    end
    if text then
        dc:seek(TASK_DESTINATION_X, TASK_DESTINATION_Y):string(text,
            COLOR_LIGHTCYAN)
    end
end

OVERLAY_WIDGETS = {
    unit_card_task_details=UnitCardTaskDetailsOverlay,
}
