--@ module=true

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')

---@enum dwarfui.UiHotkeyMenuId
UiHotkeyMenuId = immutable_enum.define({
    CITIZENS=1,
    TASKS=2,
    PLACES=3,
    LABOR=4,
    ORDERS=5,
    NOBLES=6,
    OBJECTS=7,
    JUSTICE=8,
}, 'UiHotkeyMenuId')

---@class dwarfui.UiHotkeyButtonCatalogEntry
---@field menu_id dwarfui.UiHotkeyMenuId
---@field semantic_id string
---@field action_binding string
---@field button_order integer
---@field bounds_finder fun(context: dwarfui.UiHotkeySamplingContext, entry: dwarfui.UiHotkeyButtonCatalogEntry): table|nil

---@class dwarfui.UiHotkeySamplingContext
---@field width integer|nil
---@field height integer|nil
---@field read_tile fun(x: integer, y: integer): table|nil
---@field bottom_button_bounds table[]

---@class dwarfui.UiHotkeyResolvedButton
---@field menu_id dwarfui.UiHotkeyMenuId
---@field semantic_id string
---@field action_binding string
---@field bounds {x1: integer, y1: integer, x2: integer, y2: integer}
---@field label string

---@class dwarfui.UiHotkeySnapshot
---@field active boolean
---@field layout_signature string
---@field buttons dwarfui.UiHotkeyResolvedButton[]
---@field bounds {x1: integer, y1: integer, x2: integer, y2: integer}|nil

local DEFAULT_BUTTON_CATALOG = {
    {
        menu_id=UiHotkeyMenuId.CITIZENS,
        semantic_id='citizens',
        action_binding='D_UNITLIST',
        button_order=1,
        bounds_finder=function(context, entry)
            return context.bottom_button_bounds[entry.button_order]
        end,
    },
    {
        menu_id=UiHotkeyMenuId.TASKS,
        semantic_id='tasks',
        action_binding='D_JOBLIST',
        button_order=2,
        bounds_finder=function(context, entry)
            return context.bottom_button_bounds[entry.button_order]
        end,
    },
    {
        menu_id=UiHotkeyMenuId.PLACES,
        semantic_id='places',
        action_binding='D_LOCATIONS',
        button_order=3,
        bounds_finder=function(context, entry)
            return context.bottom_button_bounds[entry.button_order]
        end,
    },
    {
        menu_id=UiHotkeyMenuId.LABOR,
        semantic_id='labor',
        action_binding='D_LABOR',
        button_order=4,
        bounds_finder=function(context, entry)
            return context.bottom_button_bounds[entry.button_order]
        end,
    },
    {
        menu_id=UiHotkeyMenuId.ORDERS,
        semantic_id='orders',
        action_binding='D_ORDERS',
        button_order=5,
        bounds_finder=function(context, entry)
            return context.bottom_button_bounds[entry.button_order]
        end,
    },
    {
        menu_id=UiHotkeyMenuId.NOBLES,
        semantic_id='nobles',
        action_binding='D_NOBLES',
        button_order=6,
        bounds_finder=function(context, entry)
            return context.bottom_button_bounds[entry.button_order]
        end,
    },
    {
        menu_id=UiHotkeyMenuId.OBJECTS,
        semantic_id='objects',
        action_binding='D_ARTLIST',
        button_order=7,
        bounds_finder=function(context, entry)
            return context.bottom_button_bounds[entry.button_order]
        end,
    },
    {
        menu_id=UiHotkeyMenuId.JUSTICE,
        semantic_id='justice',
        action_binding='D_JUSTICE',
        button_order=8,
        bounds_finder=function(context, entry)
            return context.bottom_button_bounds[entry.button_order]
        end,
    },
}

---Returns whether a tile belongs to a native UI surface.
---@param tile table|nil
---@return boolean
local function is_native_ui_tile(tile)
    if not tile then return false end
    if tile.write_to_lower then return true end
    return type(tile.tile) == 'number' and tile.tile ~= 0
end

---Discovers the rendered bounds of the native bottom-bar button group.
---@param width integer|nil
---@param height integer|nil
---@param read_tile fun(x: integer, y: integer): table|nil
---@param button_count integer
---@return table[]
local function detect_bottom_button_bounds(width, height, read_tile, button_count)
    if type(width) ~= 'number' or type(height) ~= 'number' or
            type(button_count) ~= 'number' or button_count < 1 or
            width < button_count or height < 8 then
        return {}
    end

    local band_top = math.max(0, height - 8)
    local band_bottom = height - 1
    local visited = {}

    ---Returns whether a bottom-band cell has already been scanned.
    ---@param x integer
    ---@param y integer
    ---@return boolean
    local function was_visited(x, y)
        local row = visited[y]
        return row and row[x] or false
    end

    ---Marks a bottom-band cell as scanned.
    ---@param x integer
    ---@param y integer
    local function mark_visited(x, y)
        visited[y] = visited[y] or {}
        visited[y][x] = true
    end

    local components = {}
    local directions = {
        {1, 0}, {-1, 0}, {0, 1}, {0, -1},
    }

    for y = band_top, band_bottom do
        for x = 0, width - 1 do
            if not was_visited(x, y) and is_native_ui_tile(read_tile(x, y)) then
                local queue = {{x=x, y=y}}
                mark_visited(x, y)
                local head = 1
                local x1, y1, x2, y2 = x, y, x, y
                local count = 0

                while head <= #queue do
                    local cell = queue[head]
                    head = head + 1
                    count = count + 1
                    if cell.x < x1 then x1 = cell.x end
                    if cell.y < y1 then y1 = cell.y end
                    if cell.x > x2 then x2 = cell.x end
                    if cell.y > y2 then y2 = cell.y end

                    for _, direction in ipairs(directions) do
                        local nx = cell.x + direction[1]
                        local ny = cell.y + direction[2]
                        if nx >= 0 and nx < width and
                                ny >= band_top and ny <= band_bottom and
                                not was_visited(nx, ny) and
                                is_native_ui_tile(read_tile(nx, ny)) then
                            mark_visited(nx, ny)
                            queue[#queue + 1] = {x=nx, y=ny}
                        end
                    end
                end

                local component_width = x2 - x1 + 1
                local component_height = y2 - y1 + 1
                local touches_bottom = y2 >= height - 2
                local not_huge = component_width <= math.floor(width * 0.45)
                if count >= 6 and component_width >= 3 and
                        component_height >= 2 and touches_bottom and not_huge then
                    components[#components + 1] = {
                        x1=x1, y1=y1, x2=x2, y2=y2,
                    }
                end
            end
        end
    end

    table.sort(components, function(left, right)
        local left_width = left.x2 - left.x1 + 1
        local right_width = right.x2 - right.x1 + 1
        local left_height = left.y2 - left.y1 + 1
        local right_height = right.y2 - right.y1 + 1
        local left_cell_width = left_width / button_count
        local right_cell_width = right_width / button_count
        local left_valid = left_width % button_count == 0 and
            left_cell_width >= left_height
        local right_valid = right_width % button_count == 0 and
            right_cell_width >= right_height
        if left_valid ~= right_valid then return left_valid end
        if left.x1 ~= right.x1 then return left.x1 < right.x1 end
        return left.y1 < right.y1
    end)

    local group = components[1]
    if not group then return {} end
    local group_width = group.x2 - group.x1 + 1
    local group_height = group.y2 - group.y1 + 1
    if group_width % button_count ~= 0 then return {} end
    local button_width = group_width / button_count
    if button_width < group_height then return {} end

    local bounds_list = {}
    for index=0,button_count - 1 do
        local x1 = group.x1 + index * button_width
        bounds_list[#bounds_list + 1] = {
            x1=x1,
            y1=group.y1,
            x2=x1 + button_width - 1,
            y2=group.y2,
        }
    end
    return bounds_list
end

---Returns the screen dimensions from DF's global GPS state.
---@return integer|nil width
---@return integer|nil height
local function default_dimensions_provider()
    local gps = df.global and df.global.gps
    if not gps then return nil, nil end
    return gps.dimx, gps.dimy
end

---Returns whether fortress mode is currently the active focused screen.
---@return boolean
local function default_active_provider()
    local viewscreen = dfhack.gui.getDFViewscreen(true)
    return viewscreen ~= nil and
        dfhack.gui.matchFocusString('dwarfmode/Default', viewscreen)
end

---Reads one rendered tile from the current screen.
---@param x integer
---@param y integer
---@return table|nil
local function default_read_tile(x, y)
    local screen = dfhack and dfhack.screen
    if not screen or type(screen.readTile) ~= 'function' then return nil end
    return screen.readTile(x, y)
end

---Attempts to resolve a human-readable key display token from DF/DFHack.
---@param action_binding string
---@return string|nil
local function default_binding_lookup(action_binding)
    local interface_key = df and df.interface_key and
        df.interface_key[action_binding] or nil
    if type(interface_key) ~= 'number' then return nil end

    local resolvers = {
        function()
            local screen = dfhack and dfhack.screen
            return screen and screen.getKeyDisplay and
                screen.getKeyDisplay(interface_key) or nil
        end,
        function()
            local gui = dfhack and dfhack.gui
            return gui and gui.getKeyDisplay and
                gui.getKeyDisplay(interface_key) or nil
        end,
        function()
            local internal = dfhack and dfhack.internal
            return internal and internal.getHotkeyDisplay and
                internal.getHotkeyDisplay(interface_key) or nil
        end,
    }
    for _, resolver in ipairs(resolvers) do
        local ok, value = pcall(resolver)
        if ok and type(value) == 'string' and value ~= '' then return value end
    end
end

---Returns whether a value is an integer.
---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == 'number' and value % 1 == 0
end

---Returns a copied rectangle when a bounds table is valid.
---@param bounds table|nil
---@return {x1: integer, y1: integer, x2: integer, y2: integer}|nil
local function validated_bounds(bounds)
    if type(bounds) ~= 'table' then return nil end
    if not is_integer(bounds.x1) or not is_integer(bounds.y1) or
            not is_integer(bounds.x2) or not is_integer(bounds.y2) or
            bounds.x1 > bounds.x2 or bounds.y1 > bounds.y2 then
        return nil
    end
    return {x1=bounds.x1, y1=bounds.y1, x2=bounds.x2, y2=bounds.y2}
end

---Extracts a compact display token from a raw keybinding label.
---@param raw string|nil
---@return string|nil
function normalize_hotkey_label(raw)
    if type(raw) ~= 'string' then return nil end
    local trimmed = raw:match('^%s*(.-)%s*$')
    if trimmed == '' then return nil end

    local leading_symbol = trimmed:match('^([^%w%s])')
    if leading_symbol then return leading_symbol end

    local tail = trimmed
    for token in trimmed:gmatch('[^%s%+%-]+') do tail = token end

    local function normalize_token(token)
        local function_key = token:match('^([Ff]%d%d?)$')
        if function_key then return function_key:upper() end
        local letter = token:match('([A-Za-z])')
        if letter then return letter:lower() end
        local digit = token:match('(%d)')
        if digit then return digit end
        local symbol = token:match('([^%w%s])')
        return symbol
    end

    return normalize_token(tail) or normalize_token(trimmed)
end

---@class dwarfui.UiHotkeyModel.attrs
---@field button_catalog dwarfui.UiHotkeyButtonCatalogEntry[]
---@field dimensions_provider fun(): integer|nil, integer|nil
---@field active_provider fun(): boolean
---@field read_tile fun(x: integer, y: integer): table|nil
---@field binding_lookup fun(action_binding: string, semantic_id: string): string|nil
---@field layout_signature_provider fun(width: integer|nil, height: integer|nil): string|number|nil

---@class dwarfui.UiHotkeyModel.attrs.partial: dwarfui.UiHotkeyModel.attrs

---@class dwarfui.UiHotkeyModel: dfhack.class, dwarfui.UiHotkeyModel.attrs
---@field super dfhack.class
---@field ATTRS dwarfui.UiHotkeyModel.attrs|fun(attributes: dwarfui.UiHotkeyModel.attrs.partial)
---@field cached_signature string|nil
---@field cached_bounds table<string, {x1: integer, y1: integer, x2: integer, y2: integer}|nil>
---@overload fun(init_table: dwarfui.UiHotkeyModel.attrs.partial): self
UiHotkeyModel = defclass(UiHotkeyModel)
UiHotkeyModel.ATTRS{
    button_catalog=DEFAULT_NIL,
    dimensions_provider=default_dimensions_provider,
    active_provider=default_active_provider,
    read_tile=default_read_tile,
    binding_lookup=default_binding_lookup,
    layout_signature_provider=DEFAULT_NIL,
}

---Initializes the model with deterministic cache state.
function UiHotkeyModel:init()
    self.cached_signature = nil
    self.cached_bounds = {}
    if self.button_catalog == nil or self.button_catalog == DEFAULT_NIL then
        self.button_catalog = DEFAULT_BUTTON_CATALOG
    end
end

---Clears cached layout and button bounds.
function UiHotkeyModel:clear_cache()
    self.cached_signature = nil
    self.cached_bounds = {}
end

---Returns a layout signature used to invalidate cached bounds.
---@param width integer|nil
---@param height integer|nil
---@param context dwarfui.UiHotkeySamplingContext|nil
---@return string
function UiHotkeyModel:get_layout_signature(width, height, context)
    local dimensions = ('%sx%s'):format(tostring(width), tostring(height))
    local native_parts = {}
    for _, bounds in ipairs(context and context.bottom_button_bounds or {}) do
        native_parts[#native_parts + 1] = ('%d,%d,%d,%d'):format(
            bounds.x1, bounds.y1, bounds.x2, bounds.y2)
    end
    local native_signature = #native_parts > 0 and
        '|native:' .. table.concat(native_parts, ';') or ''
    if self.layout_signature_provider == nil or
            self.layout_signature_provider == DEFAULT_NIL then
        return dimensions .. native_signature
    end
    local extra = self.layout_signature_provider(width, height)
    return dimensions .. '|' .. tostring(extra) .. native_signature
end

---Builds a shared sampling context for all catalog bounds finders.
---@param width integer|nil
---@param height integer|nil
---@return dwarfui.UiHotkeySamplingContext
function UiHotkeyModel:make_sampling_context(width, height)
    local button_count = #(self.button_catalog or {})
    return {
        width=width,
        height=height,
        read_tile=self.read_tile,
        bottom_button_bounds=detect_bottom_button_bounds(
            width, height, self.read_tile, button_count),
    }
end

---Re-samples every configured button bounds finder for this layout.
---@param width integer|nil
---@param height integer|nil
---@param context dwarfui.UiHotkeySamplingContext|nil
function UiHotkeyModel:refresh_bounds(width, height, context)
    self.cached_bounds = {}
    context = context or self:make_sampling_context(width, height)
    for _, entry in ipairs(self.button_catalog or {}) do
        if type(entry.semantic_id) == 'string' and
                type(entry.bounds_finder) == 'function' then
            local ok, result = pcall(entry.bounds_finder, context, entry)
            self.cached_bounds[entry.semantic_id] =
                ok and validated_bounds(result) or nil
        end
    end
end

---Builds one render-ready snapshot from current layout and active bindings.
---@return dwarfui.UiHotkeySnapshot
function UiHotkeyModel:build_snapshot()
    if not self.active_provider() then
        self:clear_cache()
        return {active=false, layout_signature='inactive', buttons={}, bounds=nil}
    end

    local width, height = self.dimensions_provider()
    local context = self:make_sampling_context(width, height)
    local layout_signature = self:get_layout_signature(width, height, context)
    if self.cached_signature ~= layout_signature then
        self.cached_signature = layout_signature
        self:refresh_bounds(width, height, context)
    end

    local buttons = {}
    local snapshot_bounds
    for _, entry in ipairs(self.button_catalog or {}) do
        local bounds = entry.semantic_id and self.cached_bounds[entry.semantic_id] or nil
        local raw_label = type(entry.action_binding) == 'string' and
            self.binding_lookup(entry.action_binding, entry.semantic_id) or nil
        local label = normalize_hotkey_label(raw_label)
        if bounds and label then
            table.insert(buttons, {
                menu_id=entry.menu_id,
                semantic_id=entry.semantic_id,
                action_binding=entry.action_binding,
                bounds=bounds,
                label=label,
            })
            if snapshot_bounds == nil then
                snapshot_bounds = {
                    x1=bounds.x1, y1=bounds.y1,
                    x2=bounds.x2, y2=bounds.y2,
                }
            else
                snapshot_bounds.x1 = math.min(snapshot_bounds.x1, bounds.x1)
                snapshot_bounds.y1 = math.min(snapshot_bounds.y1, bounds.y1)
                snapshot_bounds.x2 = math.max(snapshot_bounds.x2, bounds.x2)
                snapshot_bounds.y2 = math.max(snapshot_bounds.y2, bounds.y2)
            end
        end
    end
    return {
        active=true,
        layout_signature=layout_signature,
        buttons=buttons,
        bounds=snapshot_bounds,
    }
end
