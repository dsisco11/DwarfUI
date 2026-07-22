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
local TASK_PANEL_WIDTH = 32

---Paints active haul pickup and destination details in the third Overview panel.
---@param dc gui.Painter
function UnitCardTaskDetailsOverlay:render(dc)
    UnitCardTaskDetailsOverlay.super.render(self, dc)
    local unit = dfhack.gui.getSelectedUnit(true)
    local grab_text = task_details.truncate_panel_text(
        task_details.get_grab_item_text(unit), TASK_PANEL_WIDTH)
    local text = task_details.truncate_panel_text(
        task_details.get_haul_destination_text(unit), TASK_PANEL_WIDTH)
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
