--@ module=true

-- Selection support for the native Premium DF minecart route menu.

local DEFAULT_LIST_X1 = 0
local DEFAULT_LIST_X2 = 71
local DEFAULT_FIRST_ROW_TOP = 10
local DEFAULT_ROW_HEIGHT = 3
local HAULING_FOCUS = 'dwarfmode/Hauling'

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
