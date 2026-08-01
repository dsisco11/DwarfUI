--@ module=true

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')

---@enum dwarfui.HotkeyStripAxis
HotkeyStripAxis = immutable_enum.define({
    HORIZONTAL=1,
    VERTICAL=2,
}, 'HotkeyStripAxis')

---@class dwarfui.HotkeyGeometryRect
---@field x1 integer
---@field y1 integer
---@field x2 integer
---@field y2 integer

---@class dwarfui.HotkeyGeometryComponent: dwarfui.HotkeyGeometryRect
---@field cell_count integer

---@class dwarfui.HotkeyStrip
---@field bounds dwarfui.HotkeyGeometryRect
---@field elements dwarfui.HotkeyGeometryRect[]

---@class dwarfui.HotkeyStripSearchOptions
---@field expected_count integer
---@field axis dwarfui.HotkeyStripAxis
---@field component_predicate fun(component: dwarfui.HotkeyGeometryComponent): boolean|nil
---@field element_predicate fun(bounds: dwarfui.HotkeyGeometryRect, index: integer, component: dwarfui.HotkeyGeometryComponent): boolean|nil

---@class dwarfui.HotkeyGeometry
HotkeyGeometry = {}
HotkeyGeometry.HotkeyStripAxis = HotkeyStripAxis

---Returns whether a value is an integer coordinate.
---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == 'number' and value % 1 == 0
end

---Copies and validates an inclusive screen-space rectangle.
---@param bounds table|nil
---@return dwarfui.HotkeyGeometryRect|nil
function HotkeyGeometry.validate_rect(bounds)
    if type(bounds) ~= 'table' or
            not is_integer(bounds.x1) or not is_integer(bounds.y1) or
            not is_integer(bounds.x2) or not is_integer(bounds.y2) or
            bounds.x1 > bounds.x2 or bounds.y1 > bounds.y2 then
        return nil
    end
    return {
        x1=bounds.x1, y1=bounds.y1,
        x2=bounds.x2, y2=bounds.y2,
    }
end

---Returns the inclusive width of a valid rectangle.
---@param bounds dwarfui.HotkeyGeometryRect|nil
---@return integer|nil
function HotkeyGeometry.width(bounds)
    local valid = HotkeyGeometry.validate_rect(bounds)
    return valid and valid.x2 - valid.x1 + 1 or nil
end

---Returns the inclusive height of a valid rectangle.
---@param bounds dwarfui.HotkeyGeometryRect|nil
---@return integer|nil
function HotkeyGeometry.height(bounds)
    local valid = HotkeyGeometry.validate_rect(bounds)
    return valid and valid.y2 - valid.y1 + 1 or nil
end

---Returns whether two inclusive rectangles have identical bounds.
---@param left dwarfui.HotkeyGeometryRect|nil
---@param right dwarfui.HotkeyGeometryRect|nil
---@return boolean
function HotkeyGeometry.equals(left, right)
    local left_valid = HotkeyGeometry.validate_rect(left)
    local right_valid = HotkeyGeometry.validate_rect(right)
    return left_valid ~= nil and right_valid ~= nil and
        left_valid.x1 == right_valid.x1 and
        left_valid.y1 == right_valid.y1 and
        left_valid.x2 == right_valid.x2 and
        left_valid.y2 == right_valid.y2
end

---Returns whether a screen coordinate lies inside a rectangle.
---@param bounds dwarfui.HotkeyGeometryRect|nil
---@param x integer
---@param y integer
---@return boolean
function HotkeyGeometry.contains(bounds, x, y)
    local valid = HotkeyGeometry.validate_rect(bounds)
    return valid ~= nil and is_integer(x) and is_integer(y) and
        x >= valid.x1 and x <= valid.x2 and
        y >= valid.y1 and y <= valid.y2
end

---Translates a rectangle by an integer screen-space offset.
---@param bounds dwarfui.HotkeyGeometryRect|nil
---@param dx integer
---@param dy integer
---@return dwarfui.HotkeyGeometryRect|nil
function HotkeyGeometry.translate(bounds, dx, dy)
    local valid = HotkeyGeometry.validate_rect(bounds)
    if not valid or not is_integer(dx) or not is_integer(dy) then return nil end
    return {
        x1=valid.x1 + dx, y1=valid.y1 + dy,
        x2=valid.x2 + dx, y2=valid.y2 + dy,
    }
end

---Converts screen-space bounds to coordinates relative to an overlay origin.
---@param bounds dwarfui.HotkeyGeometryRect|nil
---@param origin {x: integer, y: integer}
---@return dwarfui.HotkeyGeometryRect|nil
function HotkeyGeometry.to_local(bounds, origin)
    if type(origin) ~= 'table' or not is_integer(origin.x) or
            not is_integer(origin.y) then
        return nil
    end
    return HotkeyGeometry.translate(bounds, -origin.x, -origin.y)
end

---Returns the smallest rectangle containing every valid input rectangle.
---@param rectangles table[]|nil
---@return dwarfui.HotkeyGeometryRect|nil
function HotkeyGeometry.union(rectangles)
    if type(rectangles) ~= 'table' then return nil end
    local result
    for _, bounds in ipairs(rectangles) do
        local valid = HotkeyGeometry.validate_rect(bounds)
        if not valid then return nil end
        if not result then
            result = valid
        else
            result.x1 = math.min(result.x1, valid.x1)
            result.y1 = math.min(result.y1, valid.y1)
            result.x2 = math.max(result.x2, valid.x2)
            result.y2 = math.max(result.y2, valid.y2)
        end
    end
    return result
end

---Returns the default predicate for native rendered screen cells.
---@param tile table|userdata|nil
---@return boolean
function HotkeyGeometry.is_native_tile(tile)
    local tile_type = type(tile)
    if tile_type ~= 'table' and tile_type ~= 'userdata' then return false end
    if tile.write_to_lower then return true end
    return type(tile.tile) == 'number' and tile.tile ~= 0
end

---Scans a caller-provided screen region into four-connected native components.
---@param region dwarfui.HotkeyGeometryRect
---@param read_tile fun(x: integer, y: integer): table|nil
---@param tile_predicate fun(tile: table|nil, x: integer, y: integer): boolean|nil
---@return dwarfui.HotkeyGeometryComponent[]
function HotkeyGeometry.scan_components(region, read_tile, tile_predicate)
    local bounds = HotkeyGeometry.validate_rect(region)
    if not bounds or type(read_tile) ~= 'function' then return {} end
    tile_predicate = tile_predicate or HotkeyGeometry.is_native_tile

    local visited = {}
    local function was_visited(x, y)
        return visited[y] and visited[y][x] or false
    end
    local function mark_visited(x, y)
        visited[y] = visited[y] or {}
        visited[y][x] = true
    end

    local components = {}
    local directions = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
    for y=bounds.y1,bounds.y2 do
        for x=bounds.x1,bounds.x2 do
            local tile = read_tile(x, y)
            if not was_visited(x, y) and tile_predicate(tile, x, y) then
                local queue = {{x=x, y=y}}
                mark_visited(x, y)
                local head = 1
                local x1, y1, x2, y2 = x, y, x, y
                local cell_count = 0
                while head <= #queue do
                    local cell = queue[head]
                    head = head + 1
                    cell_count = cell_count + 1
                    x1, y1 = math.min(x1, cell.x), math.min(y1, cell.y)
                    x2, y2 = math.max(x2, cell.x), math.max(y2, cell.y)
                    for _, direction in ipairs(directions) do
                        local nx = cell.x + direction[1]
                        local ny = cell.y + direction[2]
                        if nx >= bounds.x1 and nx <= bounds.x2 and
                                ny >= bounds.y1 and ny <= bounds.y2 and
                                not was_visited(nx, ny) then
                            local neighbor = read_tile(nx, ny)
                            if tile_predicate(neighbor, nx, ny) then
                                mark_visited(nx, ny)
                                queue[#queue + 1] = {x=nx, y=ny}
                            end
                        end
                    end
                end
                components[#components + 1] = {
                    x1=x1, y1=y1, x2=x2, y2=y2,
                    cell_count=cell_count,
                }
            end
        end
    end

    table.sort(components, function(left, right)
        if left.x1 ~= right.x1 then return left.x1 < right.x1 end
        return left.y1 < right.y1
    end)
    return components
end

---Partitions one component into equally sized repeated strip elements.
---@param component dwarfui.HotkeyGeometryComponent
---@param options dwarfui.HotkeyStripSearchOptions
---@return dwarfui.HotkeyStrip|nil
local function partition_component(component, options)
    local bounds = HotkeyGeometry.validate_rect(component)
    local count = options.expected_count
    if not bounds or type(count) ~= 'number' or count < 1 or count % 1 ~= 0 then
        return nil
    end
    local width = HotkeyGeometry.width(bounds)
    local height = HotkeyGeometry.height(bounds)
    local step, element_width, element_height
    if options.axis == HotkeyStripAxis.HORIZONTAL then
        if width % count ~= 0 then return nil end
        step, element_width, element_height = width / count, width / count, height
    elseif options.axis == HotkeyStripAxis.VERTICAL then
        if height % count ~= 0 then return nil end
        step, element_width, element_height = height / count, width, height / count
    else
        return nil
    end
    if element_width < 1 or element_height < 1 then return nil end

    local elements = {}
    for index=0,count - 1 do
        local element
        if options.axis == HotkeyStripAxis.HORIZONTAL then
            local x1 = bounds.x1 + index * step
            element = {x1=x1, y1=bounds.y1, x2=x1 + step - 1,
                y2=bounds.y2}
        else
            local y1 = bounds.y1 + index * step
            element = {x1=bounds.x1, y1=y1, x2=bounds.x2,
                y2=y1 + step - 1}
        end
        if options.element_predicate and not options.element_predicate(
                element, index + 1, component) then
            return nil
        end
        elements[#elements + 1] = element
    end
    return {bounds=bounds, elements=elements}
end

---Finds exactly one valid repeated strip among native components.
---@param components dwarfui.HotkeyGeometryComponent[]|nil
---@param options dwarfui.HotkeyStripSearchOptions
---@return dwarfui.HotkeyStrip|nil
---@return string|nil error_code
function HotkeyGeometry.find_repeated_strip(components, options)
    if type(components) ~= 'table' or type(options) ~= 'table' then
        return nil, 'invalid_arguments'
    end
    local candidates = {}
    for _, component in ipairs(components) do
        if (not options.component_predicate or
                options.component_predicate(component)) then
            local strip = partition_component(component, options)
            if strip then candidates[#candidates + 1] = strip end
        end
    end
    if #candidates == 0 then return nil, 'not_found' end
    if #candidates > 1 then return nil, 'ambiguous' end
    return candidates[1]
end

---Creates a stable signature from group and keyed element rectangles.
---@param group_id string
---@param group_bounds dwarfui.HotkeyGeometryRect
---@param elements table<string, dwarfui.HotkeyGeometryRect>
---@return string|nil
function HotkeyGeometry.make_signature(group_id, group_bounds, elements)
    local group = HotkeyGeometry.validate_rect(group_bounds)
    if type(group_id) ~= 'string' or group_id == '' or not group or
            type(elements) ~= 'table' then return nil end
    local keys = {}
    for element_id, bounds in pairs(elements) do
        if type(element_id) ~= 'string' or not HotkeyGeometry.validate_rect(bounds) then
            return nil
        end
        keys[#keys + 1] = element_id
    end
    table.sort(keys)
    local parts = {
        group_id,
        ('%d,%d,%d,%d'):format(group.x1, group.y1, group.x2, group.y2),
    }
    for _, element_id in ipairs(keys) do
        local bounds = elements[element_id]
        parts[#parts + 1] = ('%s=%d,%d,%d,%d'):format(
            element_id, bounds.x1, bounds.y1, bounds.x2, bounds.y2)
    end
    return table.concat(parts, '|')
end
