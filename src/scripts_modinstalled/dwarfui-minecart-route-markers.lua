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

---Returns the current DFHack focus strings.
---@return string[]
local function get_focus()
    return dfhack.gui.getCurFocus()
end

---Returns whether a screen cell belongs to a native graphics-backed panel.
---@param x integer
---@param y integer
---@return boolean
local function is_native_panel_cell(x, y)
    local tile = dfhack.screen.readTile(x, y)
    return tile and tile.write_to_lower or false
end

---Reads the native Hauling panel rectangle from its rendered tile coverage.
---The longest panel run inside the dwarfmode map region is the route panel;
---the vertical extent is then expanded from the same interior cell.
---@param sample_y integer
---@return {x1: integer, y1: integer, x2: integer, y2: integer}|nil
local function read_hauling_menu_bounds(sample_y)
    local map = guidm.getPanelLayout().map
    local best_x1, best_x2
    local run_x1
    for x=map.x1,map.x2 + 1 do
        if x <= map.x2 and is_native_panel_cell(x, sample_y) then
            run_x1 = run_x1 or x
        elseif run_x1 then
            local run_x2 = x - 1
            if not best_x1 or run_x2 - run_x1 > best_x2 - best_x1 then
                best_x1, best_x2 = run_x1, run_x2
            end
            run_x1 = nil
        end
    end
    if not best_x1 then return nil end

    local interior_x = math.min(best_x1 + 1, best_x2)
    local _, screen_height = dfhack.screen.getWindowSize()
    local y1, y2 = sample_y, sample_y
    while y1 > 0 and is_native_panel_cell(interior_x, y1 - 1) do
        y1 = y1 - 1
    end
    while y2 + 1 < screen_height and
            is_native_panel_cell(interior_x, y2 + 1) do
        y2 = y2 + 1
    end
    return {x1=best_x1, y1=y1, x2=best_x2, y2=y2}
end

---@class dwarfui.MinecartRouteMarkersOverlay: plugins.overlay.OverlayWidget
---@field selection dwarfui.MinecartRouteSelection
---@field layout dwarfui.MinecartRouteMenuLayout
---@field projection dwarfui.MinecartRouteMarkerProjection
---@field hauling_provider fun(): df.hauling_handlerst|nil
---@field focus_provider fun(): string[]
---@field mouse_provider fun(): integer|nil, integer|nil
---@field viewport_provider fun(): gui.dwarfmode.Viewport
---@field map_overlay_renderer fun(callback: fun(pos: table): any, bounds: table)
---@field bounds_provider fun(sample_y: integer): table|nil
---@field bounds_screen_width integer|nil
---@field bounds_screen_height integer|nil
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
    bounds_provider=read_hauling_menu_bounds,
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

---Reads and caches native Hauling panel bounds, refreshing only after the
---interface dimensions change.
function MinecartRouteMarkersOverlay:ensure_menu_bounds()
    local width, height = dfhack.screen.getWindowSize()
    if self.layout.bounds and self.bounds_screen_width == width and
            self.bounds_screen_height == height then
        return
    end
    local bounds = self.bounds_provider(self.layout.first_row_top + 1)
    if bounds then
        self.layout:cache_bounds(bounds)
        self.bounds_screen_width = width
        self.bounds_screen_height = height
    end
end

---Resolves the current selected route and clears it when its context vanished.
---@return df.hauling_route|nil
function MinecartRouteMarkersOverlay:resolve_selected_route()
    local hauling = self.hauling_provider()
    if not self.layout:is_supported_focus(self.focus_provider()) or
            not hauling then
        self:clear_selection()
        return nil
    end
    return self.selection:resolve_selected_route(hauling.routes)
end

---Renders one full map-tile marker while preserving the underlying map
---graphics as its transparent background.
---@param marker dwarfui.MinecartRouteMarkerDescriptor
function MinecartRouteMarkersOverlay:render_marker(marker)
    local pos = marker.world_pos
    self.map_overlay_renderer(function(candidate)
        if candidate.x == pos.x and candidate.y == pos.y then
            return marker.marker_pen
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
        dc:seek(self.layout:get_indicator_x(), y + 1):string(string.char(16),
            COLOR_YELLOW)
    end
end

---Renders the native overlay frame, then selection UI and selected stop map data.
---@param dc gui.Painter
function MinecartRouteMarkersOverlay:render(dc)
    MinecartRouteMarkersOverlay.super.render(self, dc)
    self:ensure_menu_bounds()
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
    self:ensure_menu_bounds()
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
