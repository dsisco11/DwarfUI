--@ module=true

local immutable_enum = reqscript('dwarfui/utils/immutable_enum')

---@enum dwarfui.UiHotkeyMenuId
UiHotkeyMenuId = immutable_enum.define({
    CITIZENS=1,
    LABOR=2,
    ORDERS=3,
    NOBLES=4,
    LOCATIONS=5,
    MILITARY=6,
    SQUADS=7,
    JUSTICE=8,
}, 'UiHotkeyMenuId')

---@class dwarfui.UiHotkeyButtonCatalogEntry
---@field menu_id dwarfui.UiHotkeyMenuId
---@field semantic_id string
---@field action_binding string
---@field bounds_finder fun(context: dwarfui.UiHotkeySamplingContext, entry: dwarfui.UiHotkeyButtonCatalogEntry): table|nil

---@class dwarfui.UiHotkeySamplingContext
---@field width integer|nil
---@field height integer|nil
---@field read_tile fun(x: integer, y: integer): table|nil

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

local DEFAULT_BUTTON_CATALOG = {
    {
        menu_id=UiHotkeyMenuId.CITIZENS,
        semantic_id='citizens',
        action_binding='D_CITIZEN',
        bounds_finder=function() return nil end,
    },
    {
        menu_id=UiHotkeyMenuId.LABOR,
        semantic_id='labor',
        action_binding='D_JOBLIST',
        bounds_finder=function() return nil end,
    },
    {
        menu_id=UiHotkeyMenuId.ORDERS,
        semantic_id='orders',
        action_binding='D_ORDERS',
        bounds_finder=function() return nil end,
    },
    {
        menu_id=UiHotkeyMenuId.NOBLES,
        semantic_id='nobles',
        action_binding='D_NOBLES',
        bounds_finder=function() return nil end,
    },
    {
        menu_id=UiHotkeyMenuId.LOCATIONS,
        semantic_id='locations',
        action_binding='D_LOCATIONS',
        bounds_finder=function() return nil end,
    },
    {
        menu_id=UiHotkeyMenuId.MILITARY,
        semantic_id='military',
        action_binding='D_MILITARY',
        bounds_finder=function() return nil end,
    },
    {
        menu_id=UiHotkeyMenuId.SQUADS,
        semantic_id='squads',
        action_binding='D_SQUADS',
        bounds_finder=function() return nil end,
    },
    {
        menu_id=UiHotkeyMenuId.JUSTICE,
        semantic_id='justice',
        action_binding='D_JUSTICE',
        bounds_finder=function() return nil end,
    },
}

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
    return dfhack.screen.readTile(x, y)
end

---Attempts to resolve a human-readable key display token from DF/DFHack.
---@param action_binding string
---@return string|nil
local function default_binding_lookup(action_binding)
    local resolvers = {
        function()
            local screen = dfhack and dfhack.screen
            return screen and screen.getKeyDisplay and
                screen.getKeyDisplay(action_binding) or nil
        end,
        function()
            local gui = dfhack and dfhack.gui
            return gui and gui.getKeyDisplay and
                gui.getKeyDisplay(action_binding) or nil
        end,
        function()
            local internal = dfhack and dfhack.internal
            return internal and internal.getHotkeyDisplay and
                internal.getHotkeyDisplay(action_binding) or nil
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
---@return string
function UiHotkeyModel:get_layout_signature(width, height)
    local dimensions = ('%sx%s'):format(tostring(width), tostring(height))
    if self.layout_signature_provider == nil or
            self.layout_signature_provider == DEFAULT_NIL then
        return dimensions
    end
    local extra = self.layout_signature_provider(width, height)
    return dimensions .. '|' .. tostring(extra)
end

---Builds a shared sampling context for all catalog bounds finders.
---@param width integer|nil
---@param height integer|nil
---@return dwarfui.UiHotkeySamplingContext
function UiHotkeyModel:make_sampling_context(width, height)
    return {
        width=width,
        height=height,
        read_tile=self.read_tile,
    }
end

---Re-samples every configured button bounds finder for this layout.
---@param width integer|nil
---@param height integer|nil
function UiHotkeyModel:refresh_bounds(width, height)
    self.cached_bounds = {}
    local context = self:make_sampling_context(width, height)
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
        return {active=false, layout_signature='inactive', buttons={}}
    end

    local width, height = self.dimensions_provider()
    local layout_signature = self:get_layout_signature(width, height)
    if self.cached_signature ~= layout_signature then
        self.cached_signature = layout_signature
        self:refresh_bounds(width, height)
    end

    local buttons = {}
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
        end
    end
    return {
        active=true,
        layout_signature=layout_signature,
        buttons=buttons,
    }
end
