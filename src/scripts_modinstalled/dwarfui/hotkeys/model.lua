--@ module=true

local geometry_module = reqscript('dwarfui/hotkeys/geometry')
local geometry = geometry_module.HotkeyGeometry or geometry_module
local provider_api = reqscript('dwarfui/hotkeys/layout_provider')

---@class dwarfui.HotkeyGroupModel.attrs
---@field definition dwarfui.HotkeyGroupDefinition
---@field dimensions_provider fun(): integer|nil, integer|nil
---@field active_provider fun(): boolean
---@field viewscreen_provider fun(): df.viewscreen|nil
---@field read_tile fun(x: integer, y: integer): table|nil
---@field binding_lookup fun(action_binding: string, semantic_id: string): string|nil
---@field layout_provider fun(context: dwarfui.HotkeySamplingContext, definition: dwarfui.HotkeyGroupDefinition): table|nil, dwarfui.HotkeyLayoutFailure|nil

---@class dwarfui.HotkeyGroupModel: dfhack.class, dwarfui.HotkeyGroupModel.attrs
---@field super dfhack.class
---@field ATTRS table
---@field cached_signature string|nil
---@field cached_layout dwarfui.HotkeyGroupLayout|nil
---@overload fun(init_table: table): self
HotkeyGroupModel = defclass(HotkeyGroupModel)
HotkeyGroupModel.ATTRS{
    definition=DEFAULT_NIL,
    dimensions_provider=function() return nil, nil end,
    active_provider=function() return false end,
    viewscreen_provider=function() return nil end,
    read_tile=function() return nil end,
    binding_lookup=nil,
    layout_provider=nil,
}

---Returns a compact label token from a raw DF key display.
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
    local function token_label(token)
        local function_key = token:match('^([Ff]%d%d?)$')
        if function_key then return function_key:upper() end
        local letter = token:match('([A-Za-z])')
        if letter then return letter:lower() end
        return token:match('(%d)') or token:match('([^%w%s])')
    end
    local label = token_label(tail) or token_label(trimmed)
    return label and label:lower() == label and label or label
end

---Resolves a named DF interface action to its current display token.
---@param action_binding string
---@return string|nil
local function default_binding_lookup(action_binding)
    local interface_key = df and df.interface_key and df.interface_key[action_binding] or nil
    if type(interface_key) ~= 'number' then return nil end
    local resolvers = {
        function()
            local screen = dfhack and dfhack.screen
            return screen and screen.getKeyDisplay and screen.getKeyDisplay(interface_key) or nil
        end,
        function()
            local gui = dfhack and dfhack.gui
            return gui and gui.getKeyDisplay and gui.getKeyDisplay(interface_key) or nil
        end,
        function()
            local internal = dfhack and dfhack.internal
            return internal and internal.getHotkeyDisplay and internal.getHotkeyDisplay(interface_key) or nil
        end,
    }
    for _, resolver in ipairs(resolvers) do
        local ok, value = pcall(resolver)
        if ok and type(value) == 'string' and value ~= '' then return value end
    end
end

---Initializes empty geometry cache state.
function HotkeyGroupModel:init()
    self.cached_signature = nil
    self.cached_layout = nil
    if self.binding_lookup == nil or self.binding_lookup == DEFAULT_NIL then
        self.binding_lookup = default_binding_lookup
    end
end

---Clears cached layout immediately.
function HotkeyGroupModel:clear_cache()
    self.cached_signature = nil
    self.cached_layout = nil
end

---Builds the read-only sampling context passed to a provider.
---@param width integer|nil
---@param height integer|nil
---@return dwarfui.HotkeySamplingContext
function HotkeyGroupModel:make_sampling_context(width, height)
    return {
        width=width,
        height=height,
        viewscreen=self.viewscreen_provider(),
        read_tile=self.read_tile,
    }
end

---Builds a canonical snapshot, resolving bindings independently of geometry cache state.
---@return dwarfui.HotkeyGroupSnapshot
function HotkeyGroupModel:build_snapshot()
    local definition = self.definition
    if type(definition) ~= 'table' or not self.active_provider() then
        self:clear_cache()
        return {group_id=definition and definition.group_id or '', state=provider_api.HotkeyGroupState.INACTIVE,
            active=false, layout_signature='inactive', bounds=nil, buttons={}}
    end
    local width, height = self.dimensions_provider()
    local context = self:make_sampling_context(width, height)
    local layout, failure = provider_api.invoke(self.layout_provider, context, definition)
    if not layout then
        self:clear_cache()
        return {group_id=definition.group_id, state=failure and failure.state or provider_api.HotkeyGroupState.UNAVAILABLE,
            active=true, layout_signature='unavailable:' .. tostring(failure and failure.reason or 'unknown'),
            bounds=nil, buttons={}}
    end
    if self.cached_signature ~= layout.signature then
        self.cached_signature = layout.signature
        self.cached_layout = layout
    end
    local current = self.cached_layout
    local buttons = {}
    local snapshot_bounds
    for _, button in ipairs(definition.buttons or {}) do
        local element = current.elements[button.element_id]
        local raw = type(button.action_binding) == 'string' and
            self.binding_lookup(button.action_binding, button.semantic_id) or nil
        local label = normalize_hotkey_label(raw)
        if element and label then
            local resolved = {
                semantic_id=button.semantic_id,
                action_binding=button.action_binding,
                element_id=button.element_id,
                bounds=geometry.validate_rect(element.bounds),
                label=label,
            }
            if button.menu_id ~= nil then resolved.menu_id = button.menu_id end
            buttons[#buttons + 1] = resolved
            snapshot_bounds = geometry.union({snapshot_bounds, resolved.bounds}) or resolved.bounds
        end
    end
    return {group_id=definition.group_id, state=provider_api.HotkeyGroupState.READY,
        active=true, layout_signature=current.signature, bounds=current.bounds,
        buttons=buttons}
end
