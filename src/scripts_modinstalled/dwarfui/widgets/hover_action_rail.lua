--@ module=true

local widgets = require('gui.widgets')

---Returns whether a value is an integer.
---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == 'number' and value % 1 == 0
end

---Returns whether a value is a nonnegative integer.
---@param value any
---@return boolean
local function is_nonnegative_integer(value)
    return is_integer(value) and value >= 0
end

---Returns a shallow contiguous sequence copy with no ambiguous sparse keys.
---@param values table
---@param field_name string
---@return table
local function copy_sequence(values, field_name)
    assert(type(values) == 'table', field_name .. ' must be a table')
    local count, highest = 0, 0
    for index in pairs(values) do
        assert(is_integer(index) and index > 0,
            field_name .. ' must use positive integer indexes')
        count = count + 1
        highest = math.max(highest, index)
    end
    assert(count == highest, field_name .. ' must use contiguous indexes')
    local result = {}
    for index=1,highest do table.insert(result, values[index]) end
    return result
end

---Returns an immutable copy of one rail-local anchor rectangle.
---@param anchor table|nil
---@return {x1: integer, y1: integer, x2: integer, y2: integer}
local function copy_anchor(anchor)
    assert(type(anchor) == 'table',
        'HoverActionTarget.anchor must be a rectangle table')
    for _, field in ipairs({'x1', 'y1', 'x2', 'y2'}) do
        assert(is_integer(anchor[field]),
            'HoverActionTarget.anchor.' .. field .. ' must be an integer')
    end
    assert(anchor.x2 >= anchor.x1,
        'HoverActionTarget.anchor.x2 must be greater than or equal to x1')
    assert(anchor.y2 >= anchor.y1,
        'HoverActionTarget.anchor.y2 must be greater than or equal to y1')
    return {x1=anchor.x1, y1=anchor.y1, x2=anchor.x2, y2=anchor.y2}
end

---Returns whether an instance derives from one expected DFHack class.
---@param value any
---@param expected_class table
---@return boolean
local function is_instance_of(value, expected_class)
    if type(value) ~= 'table' then return false end
    local class = getmetatable(value)
    while class do
        if class == expected_class then return true end
        class = rawget(class, 'super') or rawget(class, '__index')
    end
    return false
end

---Returns whether an instance derives from the DFHack widget base class.
---@param value any
---@return boolean
local function is_widget_instance(value)
    return is_instance_of(value, widgets.Widget)
end

---Returns the default action visibility policy.
---@param _ dwarfui.HoverActionTarget
---@return boolean
local function default_visible(_)
    return true
end

---Returns the default action enabled policy.
---@param _ dwarfui.HoverActionTarget
---@return boolean
local function default_enabled(_)
    return true
end

---@class dwarfui.HoverActionTarget: dfhack.class
---@field key string|integer Stable consumer-defined target identity.
---@field anchor {x1: integer, y1: integer, x2: integer, y2: integer} Rail-local target rectangle.
---@field payload any Opaque consumer-owned target data.
---@overload fun(init_table: {key: string|integer, anchor: table, payload?: any}): self
HoverActionTarget = defclass(HoverActionTarget)
HoverActionTarget.ATTRS{
    key=DEFAULT_NIL,
    anchor=DEFAULT_NIL,
    payload=DEFAULT_NIL,
}

---Validates stable identity and snapshots rail-local target bounds.
function HoverActionTarget:init()
    assert((type(self.key) == 'string' and self.key ~= '') or
            is_integer(self.key),
        'HoverActionTarget.key must be a non-empty string or integer')
    self.anchor = copy_anchor(self.anchor)
end

---@class dwarfui.HoverAction: dfhack.class
---@field id string Stable action identity.
---@field widget_factory fun(activate: fun(): boolean): widgets.Widget Creates the rail-owned action widget once.
---@field activate fun(target: dwarfui.HoverActionTarget): boolean|nil Performs consumer-owned work for a fresh target.
---@field visible fun(target: dwarfui.HoverActionTarget): boolean Determines whether the action is presented.
---@field enabled fun(target: dwarfui.HoverActionTarget): boolean Determines whether the action can activate.
---@field gap_after integer Cells after this action before the next action.
---@overload fun(init_table: {id: string, widget_factory: fun(activate: fun(): boolean): widgets.Widget, activate: fun(target: dwarfui.HoverActionTarget): boolean|nil, visible?: fun(target: dwarfui.HoverActionTarget): boolean, enabled?: fun(target: dwarfui.HoverActionTarget): boolean, gap_after?: integer}): self
HoverAction = defclass(HoverAction)
HoverAction.ATTRS{
    id=DEFAULT_NIL,
    widget_factory=DEFAULT_NIL,
    activate=DEFAULT_NIL,
    visible=default_visible,
    enabled=default_enabled,
    gap_after=0,
}

---Validates action identity, callbacks, and spacing.
function HoverAction:init()
    assert(type(self.id) == 'string' and self.id ~= '',
        'HoverAction.id must be a non-empty string')
    assert(type(self.widget_factory) == 'function',
        'HoverAction.widget_factory must be a function')
    assert(type(self.activate) == 'function',
        'HoverAction.activate must be a function')
    assert(type(self.visible) == 'function',
        'HoverAction.visible must be a function')
    assert(type(self.enabled) == 'function',
        'HoverAction.enabled must be a function')
    assert(is_nonnegative_integer(self.gap_after),
        'HoverAction.gap_after must be a nonnegative integer')
end

---Validates a configured list of ordered action definitions.
---@param actions table|nil
---@return dwarfui.HoverAction[]
local function copy_actions(actions)
    assert(type(actions) == 'table' and next(actions) ~= nil,
        'HoverActionRail.actions must be a non-empty action table')
    local result = copy_sequence(actions, 'HoverActionRail.actions')
    local seen_ids = {}
    for index, action in ipairs(result) do
        assert(is_instance_of(action, HoverAction),
            ('HoverActionRail.actions[%d] must be a HoverAction'):format(index))
        assert(type(action.id) == 'string' and action.id ~= '',
            ('HoverActionRail.actions[%d] has no stable ID'):format(index))
        assert(type(action.widget_factory) == 'function',
            ('HoverActionRail.actions[%d] has no widget factory'):format(index))
        assert(type(action.activate) == 'function',
            ('HoverActionRail.actions[%d] has no activation callback'):format(index))
        assert(type(action.visible) == 'function' and type(action.enabled) == 'function',
            ('HoverActionRail.actions[%d] has invalid presentation callbacks'):
                format(index))
        assert(is_nonnegative_integer(action.gap_after),
            ('HoverActionRail.actions[%d] has an invalid action gap'):format(index))
        assert(not seen_ids[action.id],
            'duplicate hover action ID: ' .. action.id)
        seen_ids[action.id] = true
    end
    return result
end

---Validates the ordered placement preferences for one rail.
---@param placements table|nil
---@return string[]
local function copy_placement_order(placements)
    local valid = {left=true, right=true, above=true, below=true}
    assert(type(placements) == 'table' and next(placements) ~= nil,
        'HoverActionRail.placement_order must be a non-empty placement table')
    local result = copy_sequence(placements, 'HoverActionRail.placement_order')
    for index, placement in ipairs(result) do
        assert(valid[placement],
            ('HoverActionRail.placement_order[%d] is invalid: %s'):format(
                index, tostring(placement)))
    end
    return result
end

---Validates an inset expressed as one scalar or per-edge integer values.
---@param inset integer|table
---@return integer|table
local function copy_inset(inset)
    if is_nonnegative_integer(inset) then return inset end
    assert(type(inset) == 'table',
        'HoverActionRail.content_inset must be a nonnegative integer or table')
    local result = {}
    local keys = {l=true, t=true, r=true, b=true, x=true, y=true}
    for key, value in pairs(inset) do
        assert(keys[key] and is_nonnegative_integer(value),
            'HoverActionRail.content_inset has an invalid edge: ' .. tostring(key))
        result[key] = value
    end
    return result
end

---Validates a static, target-sensitive, or disabled presentation value.
---@param value any
---@param field_name string
local function validate_presentation_value(value, field_name)
    assert(value == false or type(value) == 'function' or
            (value ~= nil and type(value) ~= 'boolean'),
        field_name .. ' must be false, a callback, or a static value')
end

---@class dwarfui.HoverActionRail.attrs: widgets.Widget.attrs
---@field actions dwarfui.HoverAction[] Ordered generic action definitions.
---@field target_at fun(x: integer, y: integer): dwarfui.HoverActionTarget|nil Resolves a fresh target at a rail-local pointer cell.
---@field validate_target fun(target: dwarfui.HoverActionTarget): dwarfui.HoverActionTarget|nil Re-resolves target identity before activation.
---@field context_active fun(): boolean Reports whether the owning context remains valid.
---@field mouse_provider fun(): integer|nil, integer|nil Supplies the current screen pointer cell.
---@field placement_bounds_provider fun(): table Supplies the rail-local placement bounds.
---@field placement_order string[] Preferred placements in order.
---@field action_gap integer Additional cells between every visible action.
---@field consume_scroll boolean Whether later input handling consumes wheel events in the rail.
---@field background_pen any|fun(target: dwarfui.HoverActionTarget): any|false Surface background configuration.
---@field border_style any|fun(target: dwarfui.HoverActionTarget): any|false Surface border configuration.
---@field content_inset integer|table Space between the outer surface and action widgets.

---@class dwarfui.HoverActionRail: widgets.Widget, dwarfui.HoverActionRail.attrs
---@field super widgets.Widget
---@field ATTRS dwarfui.HoverActionRail.attrs|fun(attributes: table)
---@field action_widgets widgets.Widget[] Stable widgets, one for every action definition.
---@field active_target dwarfui.HoverActionTarget|nil Currently retained target snapshot.
---@field rail_bounds table|nil Current visible rail rectangle.
---@overload fun(init_table: dwarfui.HoverActionRail.attrs): self
HoverActionRail = defclass(HoverActionRail, widgets.Widget)
HoverActionRail.ATTRS{
    actions=DEFAULT_NIL,
    target_at=DEFAULT_NIL,
    validate_target=DEFAULT_NIL,
    context_active=DEFAULT_NIL,
    mouse_provider=DEFAULT_NIL,
    placement_bounds_provider=DEFAULT_NIL,
    placement_order={'left', 'right', 'above', 'below'},
    action_gap=0,
    consume_scroll=false,
    background_pen=false,
    border_style=false,
    content_inset=0,
}

---Creates each configured action widget once and initializes empty rail state.
function HoverActionRail:init()
    for _, field in ipairs({
            'target_at', 'validate_target', 'context_active', 'mouse_provider',
            'placement_bounds_provider'}) do
        assert(type(self[field]) == 'function',
            'HoverActionRail.' .. field .. ' must be a function')
    end
    self.actions = copy_actions(self.actions)
    self.placement_order = copy_placement_order(self.placement_order)
    assert(is_nonnegative_integer(self.action_gap),
        'HoverActionRail.action_gap must be a nonnegative integer')
    assert(type(self.consume_scroll) == 'boolean',
        'HoverActionRail.consume_scroll must be a boolean')
    validate_presentation_value(self.background_pen,
        'HoverActionRail.background_pen')
    validate_presentation_value(self.border_style,
        'HoverActionRail.border_style')
    self.content_inset = copy_inset(self.content_inset)

    self.action_widgets = {}
    for _, action in ipairs(self.actions) do
        local widget = action.widget_factory(function()
            return self:activate(action)
        end)
        assert(is_widget_instance(widget),
            'HoverAction.widget_factory must return a widgets.Widget')
        table.insert(self.action_widgets, widget)
    end
    self.active_target = nil
    self.rail_bounds = nil
end

---Returns the currently retained target without refreshing its validity.
---@return dwarfui.HoverActionTarget|nil
function HoverActionRail:get_target()
    return self.active_target
end

---Temporarily provides the public activation entrypoint before input ownership.
---@param action dwarfui.HoverAction
---@return boolean activated
function HoverActionRail:activate(action)
    assert(is_instance_of(action, HoverAction),
        'HoverActionRail.activate requires a HoverAction')
    return false
end
