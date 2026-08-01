--@ module=true

-- Fullscreen map overlay for the selected native minecart route.

local overlay = require('plugins.overlay')
local guidm = require('gui.dwarfmode')
local route_model = reqscript('dwarfui/minecart_route')
local AssetButton = reqscript('dwarfui/widgets/asset_button').AssetButton
local rail_model = reqscript('dwarfui/widgets/hover_action_rail')
local tooltip = reqscript('dwarfuicore/tooltip/api')
local MarkerKind = route_model.MinecartRouteMarkerKind
local PointerPolicy = reqscript('dwarfuicore/pointer').PointerPolicy

local HAULING_FOCUS = 'dwarfmode/Hauling'
local ZOOM_ACTION_ID = 'recenter'
-- Preserve the native menu cells behind the action while making the rail's
-- background policy explicit for future actions or frame styles.
local RAIL_BACKGROUND = {fg=0, bg=0, keep_lower=true}
local RAIL_BORDER = false
local RAIL_CONTENT_INSET = 0

---Returns whether two inclusive screen rectangles have identical edges.
---@param left table|nil
---@param right table|nil
---@return boolean
local function same_bounds(left, right)
    return left and right and left.x1 == right.x1 and left.y1 == right.y1 and
        left.x2 == right.x2 and left.y2 == right.y2
end

-- Vanilla's classic STOCKS_RECENTER graphic is a cyan right arrow followed
-- by a red X. Premium replaces the same three-cell action with a 3-by-3 asset.
local STOCKS_RECENTER_CHARS = {
    '   ',
    string.char(26) .. 'X ',
    '   ',
}

---Returns a foreground pen that preserves the native panel underneath it.
---@param foreground dfhack.color
---@return dfhack.pen
local function transparent_pen(foreground)
    return {fg=foreground, bg=0, keep_lower=true}
end

local STOCKS_RECENTER_PENS = {
    {transparent_pen(0), transparent_pen(0), transparent_pen(0)},
    {transparent_pen(3), transparent_pen(4), transparent_pen(0)},
    {transparent_pen(0), transparent_pen(0), transparent_pen(0)},
}
local STOCKS_RECENTER_TOOLTIP = 'Zoom to this stop'

---Returns the active native Hauling state.
---@return df.hauling_handlerst|nil
local function get_hauling()
    return df.global.plotinfo and df.global.plotinfo.hauling or nil
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
---@field stop_rail dwarfui.HoverActionRail
---@field hauling_provider fun(): df.hauling_handlerst|nil
---@field focus_provider fun(): string[]
---@field viewport_provider fun(): gui.dwarfmode.Viewport
---@field map_overlay_renderer fun(callback: fun(pos: table): any, bounds: table)
---@field reveal_provider fun(pos: table, center: boolean, highlight: boolean)
---@field bounds_provider fun(sample_y: integer): table|nil
---@field bounds_screen_width integer|nil
---@field bounds_screen_height integer|nil
---@field map_tooltip_handles table<integer, dwarfui.MapTileTooltipRegistration>
---@field map_tooltip_order integer[]
---@field map_tooltip_route_id integer|nil
MinecartRouteMarkersOverlay = defclass(MinecartRouteMarkersOverlay,
    overlay.OverlayWidget)
MinecartRouteMarkersOverlay.ATTRS{
    desc='Marks the stops of a selected Minecart Route on the fortress map.',
    version='1',
    default_enabled=true,
    viewscreens=HAULING_FOCUS,
    hotspot=true,
    -- Clear context-owned state on the first overlay update after focus leaves
    -- Hauling instead of inheriting the five-second update throttle.
    overlay_onupdate_max_freq_seconds=0,
    fullscreen=true,
    frame={l=0, t=0, w=1, h=1},
    hauling_provider=get_hauling,
    focus_provider=function()
        return dfhack.gui.getFocusStrings(dfhack.gui.getDFViewscreen(true))
    end,
    viewport_provider=guidm.Viewport.get,
    map_overlay_renderer=guidm.renderMapOverlay,
    reveal_provider=dfhack.gui.revealInDwarfmodeMap,
    bounds_provider=read_hauling_menu_bounds,
}

---Constructs route-marker models and the one contextual stop-action rail.
function MinecartRouteMarkersOverlay:init()
    self.map_tooltip_handles = {}
    self.map_tooltip_order = {}
    self.map_tooltip_route_id = nil
    self.layout = route_model.MinecartRouteMenuLayout{}
    self.selection = route_model.MinecartRouteSelection{layout=self.layout}
    self.projection = route_model.MinecartRouteMarkerProjection{}
    local zoom = rail_model.HoverAction{
        id=ZOOM_ACTION_ID,
        widget_factory=function(activate)
            local button = AssetButton{
                view_id=ZOOM_ACTION_ID,
                frame={w=3, h=3},
                asset={page='INTERFACE_BITS', x=32, y=0},
                chars=STOCKS_RECENTER_CHARS,
                pens=STOCKS_RECENTER_PENS,
                tooltip=STOCKS_RECENTER_TOOLTIP,
                on_activate=activate,
            }
            tooltip.register(button)
            return button
        end,
        activate=function(target) return self:activate_zoom_action(target.payload) end,
    }
    self.stop_rail = rail_model.HoverActionRail{
        view_id='stop_action_rail',
        actions={zoom}, placement_order={'left'},
        pointer_policy=PointerPolicy.PASS,
        background_pen=RAIL_BACKGROUND, border_style=RAIL_BORDER,
        content_inset=RAIL_CONTENT_INSET, consume_scroll=true,
        target_at=function(x,y) return self:target_at_stop(x,y) end,
        validate_target=function(target) return self:validate_stop_target(target) end,
        context_active=function() return self.layout:is_supported_focus(self.focus_provider()) and self.hauling_provider() ~= nil end,
        placement_bounds_provider=function()
            local bounds = self.layout.bounds
            return {x1=0, y1=0, x2=bounds and bounds.x1 - 1 or 0,
                y2=df.global.gps.dimy - 1}
        end,
    }
    self:addviews{self.stop_rail}
    self.overlay_ondisable = function() self:clear_overlay_state() end
end

---Removes every exact-tile tooltip owned by this overlay.
function MinecartRouteMarkersOverlay:clear_map_tooltips()
    for _, handle in pairs(self.map_tooltip_handles) do
        tooltip.unregister_map_tile(handle)
    end
    self.map_tooltip_handles = {}
    self.map_tooltip_order = {}
    self.map_tooltip_route_id = nil
end

---Returns whether the registered same-z stop order matches fresh descriptors.
---@param stop_ids integer[]
---@return boolean
function MinecartRouteMarkersOverlay:has_map_tooltip_order(stop_ids)
    if #stop_ids ~= #self.map_tooltip_order then return false end
    for index, stop_id in ipairs(stop_ids) do
        if self.map_tooltip_order[index] ~= stop_id then return false end
    end
    return true
end

---Rebuilds exact-tile registrations in current route order.
---@param route_id integer
---@param markers dwarfui.MinecartRouteMarkerDescriptor[]
---@param stop_ids integer[]
function MinecartRouteMarkersOverlay:rebuild_map_tooltips(
        route_id, markers, stop_ids)
    self:clear_map_tooltips()
    self.map_tooltip_route_id = route_id
    for _, marker in ipairs(markers) do
        if marker.marker_kind == MarkerKind.SAME_Z and
                type(marker.stop_id) == 'number' then
            self.map_tooltip_handles[marker.stop_id] =
                tooltip.register_map_tile{
                    owner=self,
                    pos=marker.world_pos,
                    tooltip=marker.label,
                }
        end
    end
    self.map_tooltip_order = stop_ids
end

---Synchronizes same-z marker tooltips from fresh selected-route descriptors.
---@param route df.hauling_route
---@param markers dwarfui.MinecartRouteMarkerDescriptor[]
function MinecartRouteMarkersOverlay:sync_map_tooltips(route, markers)
    local stop_ids = {}
    for _, marker in ipairs(markers) do
        if marker.marker_kind == MarkerKind.SAME_Z and
                type(marker.stop_id) == 'number' then
            table.insert(stop_ids, marker.stop_id)
        end
    end
    if route.id ~= self.map_tooltip_route_id or
            not self:has_map_tooltip_order(stop_ids) then
        self:rebuild_map_tooltips(route.id, markers, stop_ids)
        return
    end
    for _, marker in ipairs(markers) do
        if marker.marker_kind == MarkerKind.SAME_Z and
                type(marker.stop_id) == 'number' then
            local handle = self.map_tooltip_handles[marker.stop_id]
            if not handle or not tooltip.update_map_tile(handle, {
                    pos=marker.world_pos,
                    tooltip=marker.label,
                }) then
                self:rebuild_map_tooltips(route.id, markers, stop_ids)
                return
            end
        end
    end
end

---Clears selected-route state and map targets without mutating native data.
function MinecartRouteMarkersOverlay:clear_selection()
    self.selection:clear()
    self:clear_map_tooltips()
end

---Clears selection and every pooled stop-row binding.
function MinecartRouteMarkersOverlay:clear_overlay_state()
    self:clear_selection()
    self.stop_rail:clear()
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

---Resolves one full native three-row stop entry into a rail target.
---@param x integer
---@param y integer
---@return dwarfui.HoverActionTarget|nil
function MinecartRouteMarkersOverlay:target_at_stop(x, y)
    local hauling, bounds = self.hauling_provider(), self.layout.bounds
    local list_x2 = bounds and bounds.x2 - 1 or nil
    if not hauling or not hauling.view_routes or not hauling.view_stops or
            not bounds or
            not self.layout:is_supported_focus(self.focus_provider()) or
            x < bounds.x1 or x > list_x2 or y < self.layout.first_row_top then
        return nil
    end
    local scroll_position = hauling.scroll_position or 0
    if type(scroll_position) ~= 'number' or scroll_position < 0 or
            scroll_position % 1 ~= 0 then
        return nil
    end
    local visible = math.floor((y-self.layout.first_row_top)/self.layout.row_height)
    local row = scroll_position + visible
    local route, stop = hauling.view_routes[row], hauling.view_stops[row]
    local top=self.layout.first_row_top+visible*self.layout.row_height
    local pos = stop and stop.pos
    if not route or not stop or not pos or type(pos.x) ~= 'number' or
            type(pos.y) ~= 'number' or type(pos.z) ~= 'number' or
            top + self.layout.row_height - 1 > bounds.y2 then
        return nil
    end
    local anchor = {x1=bounds.x1, y1=top, x2=list_x2,
        y2=top + self.layout.row_height - 1}
    return rail_model.HoverActionTarget{
        key=route.id .. ':' .. stop.id,
        anchor=anchor,
        payload={
            route_id=route.id,
            stop_id=stop.id,
            row_index=row,
            bounds=anchor,
            pos={x=pos.x, y=pos.y, z=pos.z},
            action_id=ZOOM_ACTION_ID,
        },
    }
end

---Validates a current contextual stop target against native list data.
function MinecartRouteMarkersOverlay:validate_stop_target(target)
    local payload=target and target.payload
    if not payload then return nil end
    local fresh=self:target_at_stop(payload.bounds.x1, payload.bounds.y1)
    if not fresh or fresh.key ~= target.key or
            not same_bounds(target.anchor, fresh.anchor) or
            not same_bounds(payload.bounds, fresh.payload.bounds) then
        return nil
    end
    return fresh
end

---Resolves a bound descriptor against the current flattened native row.
---@param descriptor table|nil
---@return {x: integer, y: integer, z: integer}|nil
---@return df.hauling_route|nil
function MinecartRouteMarkersOverlay:resolve_stop_action_position(descriptor)
    if not descriptor or descriptor.action_id ~= ZOOM_ACTION_ID or
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
    if not self.layout.bounds or visible_index < 0 or
            descriptor.bounds.x1 ~= self.layout.bounds.x1 or
            descriptor.bounds.x2 ~= self.layout.bounds.x2 - 1 or
            descriptor.bounds.y1 ~= self.layout.first_row_top +
                visible_index * self.layout.row_height or
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
            type(pos.z) ~= 'number' or not descriptor.pos or
            pos.x ~= descriptor.pos.x or pos.y ~= descriptor.pos.y or
            pos.z ~= descriptor.pos.z then
        return nil
    end
    return {x=pos.x, y=pos.y, z=pos.z}, route
end

---Selects the owning route, then centers and highlights its validated stop.
---@param descriptor table
---@return boolean activated
function MinecartRouteMarkersOverlay:activate_zoom_action(descriptor)
    local pos, route = self:resolve_stop_action_position(descriptor)
    if not pos then return false end
    local previous_route_id = self.selection:get_selected_route_id()
    if not self.selection:select_route(route) then return false end
    if self.selection:get_selected_route_id() ~= previous_route_id then
        self:clear_map_tooltips()
    end
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
    local route = self.selection:resolve_selected_route(hauling.routes)
    if not route then self:clear_map_tooltips() end
    return route
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
    local route = self:resolve_selected_route()
    if hauling and route then
        self:render_selection_indicator(dc, hauling)
        local markers = self.projection:project(route, self.viewport_provider())
        self:sync_map_tooltips(route, markers)
        for _, marker in ipairs(markers) do self:render_marker(marker) end
        self:render_labels(dc, markers)
    else
        self:clear_map_tooltips()
    end
    MinecartRouteMarkersOverlay.super.render(self, dc)
end

---Consumes owned button clicks before observing pass-through native row input.
---@param keys table
---@return boolean
function MinecartRouteMarkersOverlay:onInput(keys)
    self:ensure_menu_bounds()
    local hauling = self.hauling_provider()
    if self:inputToSubviews(keys) then return true end
    local mouse_x, mouse_y = self:getMousePos()
    local previous_route_id = self.selection:get_selected_route_id()
    self.selection:observe_input(keys, mouse_x, mouse_y,
        hauling, self.focus_provider())
    if self.selection:get_selected_route_id() ~= previous_route_id then
        self:clear_map_tooltips()
    end
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
    if not self.selection:resolve_selected_route(hauling.routes) then
        self:clear_map_tooltips()
    end
end

OVERLAY_WIDGETS = {
    minecart_route_markers=MinecartRouteMarkersOverlay,
}
