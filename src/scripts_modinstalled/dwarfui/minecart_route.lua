--@ module=true

local map_projection = reqscript('dwarfuicore/map_projection')

-- Selection support for the native Premium DF minecart route menu.

local DEFAULT_LIST_X1 = 0
local DEFAULT_LIST_X2 = 71
local DEFAULT_INDICATOR_X = 1
local DEFAULT_FIRST_ROW_TOP = 10
local DEFAULT_FIRST_ROW_OFFSET = 6
local DEFAULT_ROW_HEIGHT = 3
local HAULING_FOCUS = 'dwarfmode/Hauling'

-- CP437 glyphs render natively in both DF text mode and graphics-mode text.
local CP437_STOP = string.char(9)
local CP437_UP = string.char(30)
local CP437_DOWN = string.char(31)

---@enum dwarfui.MinecartRouteMarkerKind
MinecartRouteMarkerKind = {
    SAME_Z=1,
    ABOVE=2,
    BELOW=3,
}

local MARKER_STYLES = {
    [MinecartRouteMarkerKind.SAME_Z]={
        kind=MinecartRouteMarkerKind.SAME_Z, glyph=CP437_STOP,
        pen={ch=CP437_STOP:byte(), fg=10, keep_lower=true}},
    [MinecartRouteMarkerKind.ABOVE]={
        kind=MinecartRouteMarkerKind.ABOVE, glyph=CP437_UP,
        pen={ch=CP437_UP:byte(), fg=14, keep_lower=true}},
    [MinecartRouteMarkerKind.BELOW]={
        kind=MinecartRouteMarkerKind.BELOW, glyph=CP437_DOWN,
        pen={ch=CP437_DOWN:byte(), fg=12, keep_lower=true}},
}

---@class dwarfui.MinecartRouteMenuRow
---@field index integer
---@field route df.hauling_route
---@field stop df.hauling_stop|nil
---@field is_route_header boolean

---@class dwarfui.MinecartRouteMenuLayout: dfhack.class
---@field list_x1 integer
---@field list_x2 integer
---@field indicator_x integer
---@field first_row_top integer
---@field row_height integer
---@field bounds {x1: integer, y1: integer, x2: integer, y2: integer}|nil
MinecartRouteMenuLayout = defclass(MinecartRouteMenuLayout)

---Initializes the native route-list geometry defaults.
function MinecartRouteMenuLayout:init()
    self.list_x1 = self.list_x1 or DEFAULT_LIST_X1
    self.list_x2 = self.list_x2 or DEFAULT_LIST_X2
    self.indicator_x = self.indicator_x or DEFAULT_INDICATOR_X
    self.first_row_top = self.first_row_top or DEFAULT_FIRST_ROW_TOP
    self.row_height = self.row_height or DEFAULT_ROW_HEIGHT
end

---Caches the native Hauling panel bounds and derives its absolute list
---coordinates. The selection x offset remains relative to the panel origin.
---@param bounds {x1: integer, y1: integer, x2: integer, y2: integer}
function MinecartRouteMenuLayout:cache_bounds(bounds)
    self.bounds = {
        x1=bounds.x1, y1=bounds.y1, x2=bounds.x2, y2=bounds.y2,
    }
    self.list_x1 = bounds.x1
    self.list_x2 = bounds.x2
    self.first_row_top = bounds.y1 + DEFAULT_FIRST_ROW_OFFSET
end

---Returns the absolute interface x coordinate for the selection indicator.
---@return integer
function MinecartRouteMenuLayout:get_indicator_x()
    return self.list_x1 + self.indicator_x
end

---Returns whether native route rows are interactive for this focus path.
---DFHack exposes the current focus as a list, while focused model tests may
---supply one focus string directly.
---@param focus string|string[]|nil
---@return boolean
function MinecartRouteMenuLayout:is_supported_focus(focus)
    if type(focus) == 'string' then return focus == HAULING_FOCUS end
    if type(focus) ~= 'table' then return false end
    for _, focus_string in ipairs(focus) do
        if focus_string == HAULING_FOCUS then return true end
    end
    return false
end

---Returns whether a pointer lies within the native route-list column.
---@param mouse_x number|nil
---@param mouse_y number|nil
---@return boolean
function MinecartRouteMenuLayout:contains_pointer(mouse_x, mouse_y)
    return type(mouse_x) == 'number' and type(mouse_y) == 'number' and
        mouse_x >= self.list_x1 and mouse_x <= self.list_x2 and
        mouse_y >= self.first_row_top
end

---Resolves a pointer to the corresponding zero-based flattened menu row.
---@param mouse_x number|nil
---@param mouse_y number|nil
---@param hauling table|nil
---@param focus string|string[]|nil
---@return dwarfui.MinecartRouteMenuRow|nil
function MinecartRouteMenuLayout:resolve_row(mouse_x, mouse_y, hauling, focus)
    if not self:is_supported_focus(focus) or
            not self:contains_pointer(mouse_x, mouse_y) or
            not hauling or not hauling.view_routes then
        return nil
    end

    local scroll_position = hauling.scroll_position or 0
    if type(scroll_position) ~= 'number' or scroll_position < 0 then
        return nil
    end
    local visible_index = math.floor(
        (mouse_y - self.first_row_top) / self.row_height)
    local row_index = scroll_position + visible_index
    local route = hauling.view_routes[row_index]
    if not route then return nil end

    local stop = hauling.view_stops and hauling.view_stops[row_index] or nil
    return {
        index=row_index,
        route=route,
        stop=stop,
        is_route_header=stop == nil,
    }
end

---Finds the visible screen row of a selected route's native header.
---@param hauling table|nil
---@param route_id integer|nil
---@param focus string|string[]|nil
---@return integer|nil
function MinecartRouteMenuLayout:find_route_header_y(hauling, route_id, focus)
    if not self:is_supported_focus(focus) or not hauling or
            not hauling.view_routes or route_id == nil then
        return nil
    end
    local scroll_position = hauling.scroll_position or 0
    if type(scroll_position) ~= 'number' or scroll_position < 0 then return nil end
    local count = type(hauling.view_routes) == 'table' and nil or
        #hauling.view_routes
    local index = scroll_position
    while (count and index < count) or
            (not count and hauling.view_routes[index] ~= nil) do
        local route = hauling.view_routes[index]
        local stop = hauling.view_stops and hauling.view_stops[index] or nil
        if route.id == route_id and not stop then
            return self.first_row_top + (index - scroll_position) *
                self.row_height
        end
        index = index + 1
    end
end

---Finds a route by numeric ID in a zero-based DF vector or Lua sequence.
---@param routes table|nil
---@param route_id integer|nil
---@return df.hauling_route|nil
local function find_route_by_id(routes, route_id)
    if not routes or route_id == nil then return nil end

    if routes[0] ~= nil and type(routes) ~= 'table' then
        for index=0,#routes - 1 do
            local route = routes[index]
            if route.id == route_id then return route end
        end
        return nil
    elseif routes[0] ~= nil then
        local index = 0
        while routes[index] ~= nil do
            local route = routes[index]
            if route.id == route_id then return route end
            index = index + 1
        end
        return nil
    end

    for _, route in ipairs(routes) do
        if route.id == route_id then return route end
    end
end

---@class dwarfui.MinecartRouteSelection: dfhack.class
---@field layout dwarfui.MinecartRouteMenuLayout
---@field selected_route_id integer|nil
MinecartRouteSelection = defclass(MinecartRouteSelection)

---Initializes route selection with the production menu layout by default.
function MinecartRouteSelection:init()
    self.layout = self.layout or MinecartRouteMenuLayout{}
end

---Returns the currently selected numeric route ID.
---@return integer|nil
function MinecartRouteSelection:get_selected_route_id()
    return self.selected_route_id
end

---Clears the selected route ID.
function MinecartRouteSelection:clear()
    self.selected_route_id = nil
end

---Selects the supplied native route when it has a numeric ID.
---@param route df.hauling_route|nil
---@return boolean
function MinecartRouteSelection:select_route(route)
    if not route or type(route.id) ~= 'number' then return false end
    self.selected_route_id = route.id
    return true
end

---Resolves the selected ID and clears it when its route no longer exists.
---@param routes table|nil
---@return df.hauling_route|nil
function MinecartRouteSelection:resolve_selected_route(routes)
    local route = find_route_by_id(routes, self.selected_route_id)
    if not route then self:clear() end
    return route
end

---Observes a route-list click while always leaving it for native DF to handle.
---@param keys table|nil
---@param mouse_x number|nil
---@param mouse_y number|nil
---@param hauling table|nil
---@param focus string|string[]|nil
---@return false
function MinecartRouteSelection:observe_input(
        keys, mouse_x, mouse_y, hauling, focus)
    if keys and keys._MOUSE_L then
        local row = self.layout:resolve_row(mouse_x, mouse_y, hauling, focus)
        if row then self:select_route(row.route) end
    end
    return false
end

---@class dwarfui.MinecartRouteMarkerDescriptor: dfhack.class
---@field stop_id integer|nil
---@field display_index integer
---@field name string
---@field world_pos {x: integer, y: integer, z: integer}
---@field screen_pos {x: integer, y: integer, z: integer}
---@field z_delta integer
---@field marker_kind dwarfui.MinecartRouteMarkerKind
---@field marker_glyph string
---@field marker_pen table
---@field label string
---@field label_x integer
---@field label_y integer
MinecartRouteMarkerDescriptor = defclass(MinecartRouteMarkerDescriptor)
MinecartRouteMarkerDescriptor.ATTRS{
    stop_id=-1,
    display_index=0,
    name='',
    world_pos=false,
    screen_pos=false,
    z_delta=0,
    marker_kind=MinecartRouteMarkerKind.SAME_Z,
    marker_glyph=' ',
    marker_pen=false,
    label='',
    label_x=0,
    label_y=0,
}

---@class dwarfui.MinecartRouteMarkerProjection: dfhack.class
---@field ui_position_provider fun(pos: table, viewport: table): table
MinecartRouteMarkerProjection = defclass(MinecartRouteMarkerProjection)

---Returns the items in a DF vector or a conventional Lua sequence.
---@param values table|nil
---@return table[]
local function vector_values(values)
    if not values then return {} end
    local result = {}
    if values[0] ~= nil and type(values) ~= 'table' then
        local length = #values
        for index=0,length - 1 do table.insert(result, values[index]) end
    elseif values[0] ~= nil then
        local index = 0
        while values[index] ~= nil do
            table.insert(result, values[index])
            index = index + 1
        end
    else
        for _, value in ipairs(values) do table.insert(result, value) end
    end
    return result
end

---Copies a native map coordinate so descriptors retain no native position
---object.
---@param pos {x: integer, y: integer, z: integer}
---@return {x: integer, y: integer, z: integer}
local function copy_pos(pos)
    return {x=pos.x, y=pos.y, z=pos.z}
end

---Builds the user-visible text for a stop label.
---@param name string
---@param z_delta integer
---@return string
local function make_label(name, z_delta)
    local label = name ~= '' and name or '(unnamed)'
    if z_delta ~= 0 then
        label = ('%s (z%+d)'):format(label, z_delta)
    end
    return label
end

---Initializes the production world-to-interface coordinate translator.
function MinecartRouteMarkerProjection:init()
    self.ui_position_provider = self.ui_position_provider or
        map_projection.world_to_interface
end

---Anchors a label at the marker's translated UI column and two rows below it.
---The screen painter clips naturally when a marker or label is offscreen.
---@param label string
---@param marker_x integer
---@param marker_y integer
---@return string, integer, integer
local function layout_label(label, marker_x, marker_y)
    return label, marker_x, marker_y + 2
end

---Projects the selected route's visible stops into immutable render
---descriptors. Same-z stops require full visibility; other z-levels require
---only x/y visibility and are marked as projections.
---@param route df.hauling_route|nil
---@param viewport gui.dwarfmode.Viewport|nil
---@return dwarfui.MinecartRouteMarkerDescriptor[]
function MinecartRouteMarkerProjection:project(route, viewport)
    if not route or not viewport or not route.stops then return {} end

    local markers = {}
    for display_index, stop in ipairs(vector_values(route.stops)) do
        local pos = stop.pos
        if pos then
            local z_delta = pos.z - viewport.z
            local visible = z_delta == 0 and viewport:isVisible(pos) or
                z_delta ~= 0 and viewport:isVisibleXY(pos)
            if visible then
                local style = z_delta == 0 and
                    MARKER_STYLES[MinecartRouteMarkerKind.SAME_Z] or
                    z_delta > 0 and
                    MARKER_STYLES[MinecartRouteMarkerKind.ABOVE] or
                    MARKER_STYLES[MinecartRouteMarkerKind.BELOW]
                local screen_pos = self.ui_position_provider(pos, viewport)
                local label, label_x, label_y = layout_label(
                    make_label(stop.name or '', z_delta), screen_pos.x,
                    screen_pos.y)
                table.insert(markers, MinecartRouteMarkerDescriptor{
                    stop_id=stop.id,
                    display_index=display_index,
                    name=stop.name or '',
                    world_pos=copy_pos(pos),
                    screen_pos=copy_pos(screen_pos),
                    z_delta=z_delta,
                    marker_kind=style.kind,
                    marker_glyph=style.glyph,
                    marker_pen={
                        ch=style.pen.ch,
                        fg=style.pen.fg,
                        keep_lower=style.pen.keep_lower,
                    },
                    label=label,
                    label_x=label_x,
                    label_y=label_y,
                })
            end
        end
    end
    return markers
end
