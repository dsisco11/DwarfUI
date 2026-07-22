--@ module=true

-- Fullscreen map overlay for the selected native minecart route.

local overlay = require('plugins.overlay')
local guidm = require('gui.dwarfmode')
local route_model = reqscript('dwarfui/minecart_route')

local HAULING_FOCUS = 'dwarfmode/Hauling'

---Returns the active native Hauling state.
---@return df.hauling_handlerst|nil
local function get_hauling()
    return df.global.plotinfo and df.global.plotinfo.hauling or nil
end

---Returns the current DFHack focus string.
---@return string|nil
local function get_focus()
    return dfhack.gui.getCurFocus()
end

---@class dwarfui.MinecartRouteMarkersOverlay: plugins.overlay.OverlayWidget
---@field selection dwarfui.MinecartRouteSelection
---@field layout dwarfui.MinecartRouteMenuLayout
---@field projection dwarfui.MinecartRouteMarkerProjection
---@field hauling_provider fun(): df.hauling_handlerst|nil
---@field focus_provider fun(): string|nil
---@field mouse_provider fun(): integer|nil, integer|nil
---@field viewport_provider fun(): gui.dwarfmode.Viewport
---@field map_overlay_renderer fun(callback: fun(pos: table): any, bounds: table)
MinecartRouteMarkersOverlay = defclass(MinecartRouteMarkersOverlay,
    overlay.OverlayWidget)
MinecartRouteMarkersOverlay.ATTRS{
    desc='Marks the stops of a selected Minecart Route on the fortress map.',
    version='1',
    default_enabled=true,
    viewscreens=HAULING_FOCUS,
    hotspot=true,
    fullscreen=true,
    frame={l=0, t=0, w=1, h=1},
    hauling_provider=get_hauling,
    focus_provider=get_focus,
    mouse_provider=dfhack.screen.getMousePos,
    viewport_provider=guidm.Viewport.get,
    map_overlay_renderer=guidm.renderMapOverlay,
}

---Constructs the selection, native-layout, and marker-projection models.
function MinecartRouteMarkersOverlay:init()
    self.layout = route_model.MinecartRouteMenuLayout{}
    self.selection = route_model.MinecartRouteSelection{layout=self.layout}
    self.projection = route_model.MinecartRouteMarkerProjection{}
    self.overlay_ondisable = function() self:clear_selection() end
end

---Clears selected-route state without mutating native route data.
function MinecartRouteMarkersOverlay:clear_selection()
    self.selection:clear()
end

---Expands the transparent hit-test and render host across the parent screen.
---@param parent_rect gui.ViewRect
function MinecartRouteMarkersOverlay:preUpdateLayout(parent_rect)
    self.frame.w = parent_rect.width
    self.frame.h = parent_rect.height
end

---Resolves the current selected route and clears it when its context vanished.
---@return df.hauling_route|nil
function MinecartRouteMarkersOverlay:resolve_selected_route()
    local hauling = self.hauling_provider()
    if self.focus_provider() ~= HAULING_FOCUS or not hauling then
        self:clear_selection()
        return nil
    end
    return self.selection:resolve_selected_route(hauling.routes)
end

---Renders one marker through DFHack's map-overlay compositor.
---@param marker dwarfui.MinecartRouteMarkerDescriptor
function MinecartRouteMarkersOverlay:render_marker(marker)
    local pos = marker.world_pos
    self.map_overlay_renderer(function(candidate)
        if candidate.x == pos.x and candidate.y == pos.y then
            return marker.marker_pen.fg, marker.marker_glyph
        end
    end, {x1=pos.x, x2=pos.x, y1=pos.y, y2=pos.y})
end

---Renders marker labels inside the visible map viewport.
---@param dc gui.Painter
---@param markers dwarfui.MinecartRouteMarkerDescriptor[]
function MinecartRouteMarkersOverlay:render_labels(dc, markers)
    for _, marker in ipairs(markers) do
        dc:seek(marker.label_x, marker.label_y):string(marker.label,
            marker.marker_pen.fg)
    end
end

---Renders a visible indicator over the selected native route header.
---@param dc gui.Painter
---@param hauling df.hauling_handlerst
function MinecartRouteMarkersOverlay:render_selection_indicator(dc, hauling)
    local y = self.layout:find_route_header_y(hauling,
        self.selection:get_selected_route_id(), self.focus_provider())
    if y and y >= 0 and y < df.global.gps.dimy then
        dc:seek(self.layout.list_x1, y + 1):string(string.char(16),
            COLOR_YELLOW)
    end
end

---Renders the native overlay frame, then selection UI and selected stop map data.
---@param dc gui.Painter
function MinecartRouteMarkersOverlay:render(dc)
    MinecartRouteMarkersOverlay.super.render(self, dc)
    local hauling = self.hauling_provider()
    local route = self:resolve_selected_route()
    if not hauling or not route then return end
    self:render_selection_indicator(dc, hauling)
    local markers = self.projection:project(route, self.viewport_provider())
    for _, marker in ipairs(markers) do self:render_marker(marker) end
    self:render_labels(dc, markers)
end

---Observes a native route-list click while leaving all native input unconsumed.
---@param keys table
---@return false
function MinecartRouteMarkersOverlay:onInput(keys)
    local mouse_x, mouse_y = self.mouse_provider()
    self.selection:observe_input(keys, mouse_x, mouse_y,
        self.hauling_provider(), self.focus_provider())
    return false
end

---Clears selection when the Hauling screen closes or the world unloads.
function MinecartRouteMarkersOverlay:overlay_onupdate()
    self:resolve_selected_route()
end

OVERLAY_WIDGETS = {
    minecart_route_markers=MinecartRouteMarkersOverlay,
}
