--@ module=true

-- Test-owned overlay used only while DwarfSpec stages this file.

local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')
local tooltip = reqscript('dwarfui/tooltip')

---@class tests.TooltipOverlay: plugins.overlay.OverlayWidget
local TooltipOverlay = defclass(nil, overlay.OverlayWidget)
TooltipOverlay.ATTRS{
    default_enabled=true,
    default_pos={x=1, y=1},
    desc='DwarfUI tooltip test overlay',
    frame={w=8, h=4},
    viewscreens='dwarfmode',
}

---Builds the registered target inside the intentionally clipped overlay root.
function TooltipOverlay:init()
    self.tooltip_target = widgets.Label{
        view_id='tooltip_target',
        frame={l=0, t=0, r=0, b=0},
        text=' ',
        tooltip='Automation overlay tooltip outside its narrow root.',
    }
    self:addviews{self.tooltip_target}
    tooltip.register(self.tooltip_target)
end

---Releases the overlay target when the overlay framework disposes it.
function TooltipOverlay:onDismiss()
    tooltip.unregister(self.tooltip_target)
    TooltipOverlay.super.onDismiss(self)
end

OVERLAY_WIDGETS = {tooltip_probe=TooltipOverlay}

return _ENV
