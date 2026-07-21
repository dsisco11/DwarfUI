--@ module=true

-- Test-owned source used only for real overlay registration integration.

local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')
local tooltip = reqscript('dwarfui/tooltip')

---@class tests.TooltipRegistrationOverlay: plugins.overlay.OverlayWidget
local TooltipRegistrationOverlay = defclass(nil, overlay.OverlayWidget)
TooltipRegistrationOverlay.ATTRS{
    default_enabled=true,
    default_pos={x=1, y=1},
    desc='DwarfUI tooltip registration probe',
    frame={w=8, h=4},
    viewscreens='dwarfmode',
}

---Builds the target inside the intentionally clipped registered overlay.
function TooltipRegistrationOverlay:init()
    self.tooltip_target = widgets.Label{
        frame={l=0, t=0, r=0, b=0},
        text=' ',
        tooltip='Automation overlay tooltip outside its narrow root.',
    }
    self:addviews{self.tooltip_target}
    tooltip.register(self.tooltip_target)
end

---Releases the product registration when the overlay is disposed.
function TooltipRegistrationOverlay:onDismiss()
    tooltip.unregister(self.tooltip_target)
    TooltipRegistrationOverlay.super.onDismiss(self)
end

OVERLAY_WIDGETS = {tooltip_probe=TooltipRegistrationOverlay}

return _ENV
