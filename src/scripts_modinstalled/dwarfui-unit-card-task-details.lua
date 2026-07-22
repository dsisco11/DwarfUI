--@ module=true

-- Unit-card overlay for active haul-task destination details.

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
local TASK_DESTINATION_Y = 32

---Paints the active hauling destination in the third left-hand Overview panel.
---@param dc gui.Painter
function UnitCardTaskDetailsOverlay:render(dc)
    UnitCardTaskDetailsOverlay.super.render(self, dc)
    local unit = dfhack.gui.getSelectedUnit(true)
    local text = task_details.get_haul_destination_text(unit)
    if not text then return end
    dc:seek(TASK_DESTINATION_X, TASK_DESTINATION_Y):string(text,
        COLOR_LIGHTCYAN)
end

OVERLAY_WIDGETS = {
    unit_card_task_details=UnitCardTaskDetailsOverlay,
}
