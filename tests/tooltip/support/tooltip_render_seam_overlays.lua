--@ module=true

-- Test-owned overlays for characterizing the native final-render seam.

local gui = require('gui')
local overlay = require('plugins.overlay')

local PROBE_X = 2
local PROBE_Y = 2

---Paints one screen-global sentinel through the supplied overlay painter.
---@param dc gui.Painter
---@param character string
---@param background integer
local function paint_sentinel(dc, character, background)
    gui.Painter.new():seek(PROBE_X, PROBE_Y):char(character, {
        fg=COLOR_WHITE,
        bg=background,
    })
end

---@class tests.TooltipRenderViewscreenOverlay:
---    plugins.overlay.OverlayWidget
local TooltipRenderViewscreenOverlay =
    defclass(nil, overlay.OverlayWidget)
TooltipRenderViewscreenOverlay.ATTRS{
    default_enabled=true,
    desc='DwarfUI tooltip viewscreen render-seam probe',
    fullscreen=true,
    viewscreens='dwarfmode',
}

---Records and paints one viewscreen-specific overlay render.
---@param dc gui.Painter
function TooltipRenderViewscreenOverlay:onRenderBody(dc)
    self.render_count = (self.render_count or 0) + 1
    paint_sentinel(dc, 'V', COLOR_RED)
end

---@class tests.TooltipRenderAllOverlay: plugins.overlay.OverlayWidget
local TooltipRenderAllOverlay = defclass(nil, overlay.OverlayWidget)
TooltipRenderAllOverlay.ATTRS{
    default_enabled=true,
    desc='DwarfUI tooltip all-viewscreens render-seam probe',
    fullscreen=true,
    viewscreens='all',
}

---Records and paints one all-viewscreens overlay render.
---@param dc gui.Painter
function TooltipRenderAllOverlay:onRenderBody(dc)
    self.render_count = (self.render_count or 0) + 1
    paint_sentinel(dc, 'A', COLOR_BLUE)
end

OVERLAY_WIDGETS = {
    viewscreen_probe=TooltipRenderViewscreenOverlay,
    all_probe=TooltipRenderAllOverlay,
}

return _ENV
