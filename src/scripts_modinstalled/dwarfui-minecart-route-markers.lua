--@ module=true

-- Fullscreen map overlay for the selected native minecart route.

local overlay = require('plugins.overlay')
local guidm = require('gui.dwarfmode')
local route_model = reqscript('dwarfui/minecart_route')
local stop_action_model = reqscript('dwarfui/minecart_stop_actions')

local HAULING_FOCUS = 'dwarfmode/Hauling'
local ZOOM_ACTION_ID = 'recenter'

-- Vanilla's classic STOCKS_RECENTER graphic is a cyan right arrow followed
-- by a red X. Premium replaces the same three-cell action with a 3-by-3 asset.
local STOCKS_RECENTER_CHARS = {
    '   ',
    string.char(26) .. 'X ',
    '   ',
}
local STOCKS_RECENTER_PENS = {
    {0, 0, 0},
    {3, 4, 0},
    {0, 0, 0},
}
local STOCKS_RECENTER_TOOLTIP = string.char(26) .. ' X'

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
---@field stop_actions dwarfui.MinecartStopActionDefinition[]
---@field stop_action_layout dwarfui.MinecartStopActionLayout
---@field stop_action_pool dwarfui.MinecartStopActionPool
---@field extra_stop_actions dwarfui.MinecartStopActionDefinition[]|false
---@field hauling_provider fun(): df.hauling_handlerst|nil
---@field focus_provider fun(): string[]
---@field mouse_provider fun(): integer|nil, integer|nil
---@field viewport_provider fun(): gui.dwarfmode.Viewport
---@field map_overlay_renderer fun(callback: fun(pos: table): any, bounds: table)
---@field reveal_provider fun(pos: table, center: boolean, highlight: boolean)
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
    reveal_provider=dfhack.gui.revealInDwarfmodeMap,
    bounds_provider=read_hauling_menu_bounds,
    extra_stop_actions=false,
}

---Constructs route-marker models and the visible stop-action button pool.
function MinecartRouteMarkersOverlay:init()
    self.layout = route_model.MinecartRouteMenuLayout{}
    self.selection = route_model.MinecartRouteSelection{layout=self.layout}
    self.projection = route_model.MinecartRouteMarkerProjection{}
    self.stop_actions = {
        stop_action_model.MinecartStopActionDefinition{
            id=ZOOM_ACTION_ID,
            width=3,
            height=3,
            asset={page='INTERFACE_BITS', x=32, y=0},
            chars=STOCKS_RECENTER_CHARS,
            pens=STOCKS_RECENTER_PENS,
            tooltip=STOCKS_RECENTER_TOOLTIP,
            on_activate=function(descriptor)
                self:activate_zoom_action(descriptor)
            end,
        },
    }
    for _, action in ipairs(self.extra_stop_actions or {}) do
        table.insert(self.stop_actions, action)
    end
    self.stop_action_layout = stop_action_model.MinecartStopActionLayout{
        actions=self.stop_actions,
    }
    self.stop_action_pool = stop_action_model.MinecartStopActionPool{
        on_button_created=function(button) self:addviews{button} end,
    }
    self.overlay_ondisable = function() self:clear_overlay_state() end
end

---Clears selected-route state without mutating native route data.
function MinecartRouteMarkersOverlay:clear_selection()
    self.selection:clear()
end

---Clears selection and every pooled stop-row binding.
function MinecartRouteMarkersOverlay:clear_overlay_state()
    self:clear_selection()
    self.stop_action_pool:clear()
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

---Rebuilds current visible stop actions and rebinds their pooled buttons.
---@param hauling df.hauling_handlerst|nil
function MinecartRouteMarkersOverlay:refresh_stop_actions(hauling)
    if not self.layout:is_supported_focus(self.focus_provider()) then
        self.stop_action_pool:clear()
        return
    end
    local descriptors = self.stop_action_layout:build(hauling, self.layout)
    self.stop_action_pool:bind(descriptors, self.frame_body)
end

---Resolves a bound descriptor against the current flattened native row.
---@param descriptor dwarfui.MinecartStopActionDescriptor|nil
---@return {x: integer, y: integer, z: integer}|nil
function MinecartRouteMarkersOverlay:resolve_stop_action_position(descriptor)
    if not descriptor or
            not self.layout:is_supported_focus(self.focus_provider()) then
        return nil
    end
    local hauling = self.hauling_provider()
    if not hauling or not hauling.view_routes or not hauling.view_stops then
        return nil
    end

    local scroll_position = hauling.scroll_position or 0
    if type(scroll_position) ~= 'number' then return nil end
    local visible_index = descriptor.row_index - scroll_position
    if visible_index < 0 or
            descriptor.bounds.y1 ~= self.layout.first_row_top +
                visible_index * self.layout.row_height or
            not self.layout.bounds or
            descriptor.bounds.y2 > self.layout.bounds.y2 then
        return nil
    end

    local route = hauling.view_routes[descriptor.row_index]
    local stop = hauling.view_stops[descriptor.row_index]
    if not route or not stop or route.id ~= descriptor.route_id or
            stop.id ~= descriptor.stop_id then
        return nil
    end
    local pos = stop.pos
    if not pos or type(pos.x) ~= 'number' or type(pos.y) ~= 'number' or
            type(pos.z) ~= 'number' then
        return nil
    end
    return {x=pos.x, y=pos.y, z=pos.z}
end

---Centers and highlights the current position of a validated stop action.
---@param descriptor dwarfui.MinecartStopActionDescriptor
---@return boolean activated
function MinecartRouteMarkersOverlay:activate_zoom_action(descriptor)
    local pos = self:resolve_stop_action_position(descriptor)
    if not pos then return false end
    self.reveal_provider(pos, true, true)
    return true
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

---Renders selected stop map data, then draws action buttons as the top layer.
---@param dc gui.Painter
function MinecartRouteMarkersOverlay:render(dc)
    self:ensure_menu_bounds()
    local hauling = self.hauling_provider()
    self:refresh_stop_actions(hauling)
    local route = self:resolve_selected_route()
    if hauling and route then
        self:render_selection_indicator(dc, hauling)
        local markers = self.projection:project(route, self.viewport_provider())
        for _, marker in ipairs(markers) do self:render_marker(marker) end
        self:render_labels(dc, markers)
    end
    MinecartRouteMarkersOverlay.super.render(self, dc)
end

---Consumes owned button clicks before observing pass-through native row input.
---@param keys table
---@return boolean
function MinecartRouteMarkersOverlay:onInput(keys)
    self:ensure_menu_bounds()
    local hauling = self.hauling_provider()
    self:refresh_stop_actions(hauling)
    if self:inputToSubviews(keys) then return true end
    local mouse_x, mouse_y = self.mouse_provider()
    self.selection:observe_input(keys, mouse_x, mouse_y,
        hauling, self.focus_provider())
    return false
end

---Clears selection when the Hauling screen closes or the world unloads.
function MinecartRouteMarkersOverlay:overlay_onupdate()
    local hauling = self.hauling_provider()
    if not self.layout:is_supported_focus(self.focus_provider()) or
            not hauling then
        self:clear_overlay_state()
        return
    end
    self.selection:resolve_selected_route(hauling.routes)
end

OVERLAY_WIDGETS = {
    minecart_route_markers=MinecartRouteMarkersOverlay,
}
