--@ module=true

-- Selection support for the native Premium DF minecart route menu.

local DEFAULT_LIST_X1 = 0
local DEFAULT_LIST_X2 = 71
local DEFAULT_FIRST_ROW_TOP = 10
local DEFAULT_ROW_HEIGHT = 3
local HAULING_FOCUS = 'dwarfmode/Hauling'

-- CP437 glyphs render natively in both DF text mode and graphics-mode text.
local CP437_STOP = string.char(15)
local CP437_UP = string.char(24)
local CP437_DOWN = string.char(25)

local MARKER_STYLES = {
    same_z={kind='same_z', glyph=CP437_STOP, pen={fg=10}},
    above={kind='above', glyph=CP437_UP, pen={fg=14}},
    below={kind='below', glyph=CP437_DOWN, pen={fg=12}},
}

---@class dwarfui.MinecartRouteMenuRow
---@field index integer
---@field route df.hauling_route
---@field stop df.hauling_stop|nil
---@field is_route_header boolean

---@class dwarfui.MinecartRouteMenuLayout: dfhack.class
---@field list_x1 integer
---@field list_x2 integer
---@field first_row_top integer
---@field row_height integer
MinecartRouteMenuLayout = defclass(MinecartRouteMenuLayout)

---Initializes the native route-list geometry defaults.
function MinecartRouteMenuLayout:init()
    self.list_x1 = self.list_x1 or DEFAULT_LIST_X1
    self.list_x2 = self.list_x2 or DEFAULT_LIST_X2
    self.first_row_top = self.first_row_top or DEFAULT_FIRST_ROW_TOP
    self.row_height = self.row_height or DEFAULT_ROW_HEIGHT
end

---Returns whether native route rows are interactive for this focus path.
---@param focus string|nil
---@return boolean
function MinecartRouteMenuLayout:is_supported_focus(focus)
    return focus == HAULING_FOCUS
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
---@param focus string|nil
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

---Finds a route by numeric ID in a zero-based DF vector or Lua sequence.
---@param routes table|nil
---@param route_id integer|nil
---@return df.hauling_route|nil
local function find_route_by_id(routes, route_id)
    if not routes or route_id == nil then return nil end

    if routes[0] ~= nil then
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
---@param focus string|nil
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
---@field marker_kind 'same_z'|'above'|'below'
---@field marker_glyph string
---@field marker_pen table
---@field label string
---@field label_x integer
---@field label_y integer
MinecartRouteMarkerDescriptor = defclass(MinecartRouteMarkerDescriptor)

---@class dwarfui.MinecartRouteMarkerProjection: dfhack.class
MinecartRouteMarkerProjection = defclass(MinecartRouteMarkerProjection)

---Returns the items in a DF vector or a conventional Lua sequence.
---@param values table|nil
---@return table[]
local function vector_values(values)
    if not values then return {} end
    local result = {}
    if values[0] ~= nil then
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

---Returns whether the supplied horizontal label span is inside the map.
---@param x integer
---@param width integer
---@param viewport gui.dwarfmode.Viewport
---@return boolean
local function fits_horizontally(x, width, viewport)
    return x >= 0 and x + width <= viewport.width
end

---Returns whether a label span conflicts with an occupied label span.
---@param occupied table[]
---@param x integer
---@param y integer
---@param width integer
---@return boolean
local function conflicts(occupied, x, y, width)
    for _, span in ipairs(occupied) do
        if span.y == y and x < span.x + span.width and
                span.x < x + width then
            return true
        end
    end
    return false
end

---Finds a deterministic free map row for a label without changing its marker
---position.
---@param occupied table[]
---@param preferred_y integer
---@param x integer
---@param width integer
---@param viewport gui.dwarfmode.Viewport
---@return integer|nil
local function find_label_row(occupied, preferred_y, x, width, viewport)
    for offset=0, viewport.height - 1 do
        local rows = offset == 0 and {preferred_y} or {
            preferred_y + offset, preferred_y - offset,
        }
        for _, y in ipairs(rows) do
            if y >= 0 and y < viewport.height and
                    not conflicts(occupied, x, y, width) then
                return y
            end
        end
    end
end

---Chooses a left or right map-contained label placement, truncating only when
---neither full placement fits.
---@param label string
---@param marker_x integer
---@param marker_y integer
---@param occupied table[]
---@param viewport gui.dwarfmode.Viewport
---@return string, integer, integer
local function layout_label(label, marker_x, marker_y, occupied, viewport)
    local width = #label
    local candidates = {
        {x=marker_x + 1, width=width},
        {x=marker_x - width, width=width},
    }
    for _, candidate in ipairs(candidates) do
        if fits_horizontally(candidate.x, candidate.width, viewport) then
            local y = find_label_row(occupied, marker_y, candidate.x,
                candidate.width, viewport)
            if y then return label, candidate.x, y end
        end
    end

    local left_width = math.max(0, marker_x)
    local right_width = math.max(0, viewport.width - marker_x - 1)
    local available_width = math.max(left_width, right_width)
    if available_width == 0 then return '', marker_x, marker_y end
    local truncated = label:sub(1, available_width)
    local x = right_width >= left_width and marker_x + 1 or
        marker_x - available_width
    local y = find_label_row(occupied, marker_y, x, #truncated, viewport) or
        marker_y
    return truncated, x, y
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
    local occupied = {}
    for display_index, stop in ipairs(vector_values(route.stops)) do
        local pos = stop.pos
        if pos then
            local z_delta = pos.z - viewport.z
            local visible = z_delta == 0 and viewport:isVisible(pos) or
                z_delta ~= 0 and viewport:isVisibleXY(pos)
            if visible then
                local style = z_delta == 0 and MARKER_STYLES.same_z or
                    z_delta > 0 and MARKER_STYLES.above or MARKER_STYLES.below
                local screen_pos = viewport:tileToScreen(pos)
                local label, label_x, label_y = layout_label(
                    make_label(stop.name or '', z_delta), screen_pos.x,
                    screen_pos.y, occupied, viewport)
                table.insert(occupied, {x=label_x, y=label_y, width=#label})
                table.insert(markers, MinecartRouteMarkerDescriptor{
                    stop_id=stop.id,
                    display_index=display_index,
                    name=stop.name or '',
                    world_pos=copy_pos(pos),
                    screen_pos=copy_pos(screen_pos),
                    z_delta=z_delta,
                    marker_kind=style.kind,
                    marker_glyph=style.glyph,
                    marker_pen={fg=style.pen.fg},
                    label=label,
                    label_x=label_x,
                    label_y=label_y,
                })
            end
        end
    end
    return markers
end
