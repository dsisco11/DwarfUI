--@ module=true

local gui = require('gui')
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

---Returns four normalized per-edge content inset values.
---@param inset integer|table
---@return integer left
---@return integer top
---@return integer right
---@return integer bottom
local function inset_edges(inset)
    if type(inset) == 'number' then return inset, inset, inset, inset end
    return inset.l or inset.x or 0,
        inset.t or inset.y or 0,
        inset.r or inset.x or 0,
        inset.b or inset.y or 0
end

---Returns a copy of one widget frame with supplied body-relative coordinates.
---@param frame table|nil
---@param left integer
---@param top integer
---@param width integer
---@param height integer
---@return table
local function placed_frame(frame, left, top, width, height)
    local result = {}
    for key, value in pairs(frame or {}) do result[key] = value end
    result.l, result.t, result.w, result.h = left, top, width, height
    result.r, result.b = nil, nil
    return result
end

---Returns a callback result or a static presentation value.
---@param value any
---@param target dwarfui.HoverActionTarget
---@return any
local function resolve_presentation_value(value, target)
    if type(value) == 'function' then return value(target) end
    return value
end

---Parses a nontransparent rail background through DFHack's pen API.
---@param value any
---@return dfhack.pen|false
local function parse_background(value)
    if value == false then return false end
    assert(dfhack and dfhack.pen and type(dfhack.pen.parse) == 'function',
        'HoverActionRail requires dfhack.pen.parse for a background pen')
    return dfhack.pen.parse(value)
end

---Validates a static, target-sensitive, or disabled presentation value.
---@param value any
---@param field_name string
local function validate_presentation_value(value, field_name)
    assert(value == false or type(value) == 'function' or
            (value ~= nil and type(value) ~= 'boolean'),
        field_name .. ' must be false, a callback, or a static value')
end

---Validates a value returned by a target-sensitive presentation callback.
---@param value any
---@param field_name string
local function validate_resolved_presentation_value(value, field_name)
    assert(value == false or (value ~= nil and type(value) ~= 'boolean' and
            type(value) ~= 'function'),
        field_name .. ' callback returned an invalid presentation value')
end

---Returns a copied rail-local rectangle after validating its inclusive edges.
---@param bounds table|nil
---@return {x1: integer, y1: integer, x2: integer, y2: integer}
local function copy_bounds(bounds)
    assert(type(bounds) == 'table',
        'HoverActionRail.placement_bounds_provider must return a rectangle')
    for _, field in ipairs({'x1', 'y1', 'x2', 'y2'}) do
        assert(is_integer(bounds[field]),
            'HoverActionRail placement bound ' .. field .. ' must be an integer')
    end
    assert(bounds.x2 >= bounds.x1 and bounds.y2 >= bounds.y1,
        'HoverActionRail placement bounds must have nonnegative dimensions')
    return {x1=bounds.x1, y1=bounds.y1, x2=bounds.x2, y2=bounds.y2}
end

---Returns whether one complete outer rectangle fits inside placement bounds.
---@param bounds table
---@param rectangle table
---@return boolean
local function fits_bounds(bounds, rectangle)
    return rectangle.x1 >= bounds.x1 and rectangle.y1 >= bounds.y1 and
        rectangle.x2 <= bounds.x2 and rectangle.y2 <= bounds.y2
end

---Returns one candidate outer surface rectangle for a supported placement.
---@param placement string
---@param anchor table
---@param width integer
---@param height integer
---@param target_gap integer
---@return table
local function placement_rectangle(
        placement, anchor, width, height, target_gap)
    local left, top
    if placement == 'left' then
        left = anchor.x1 - target_gap - width
        top = math.floor((anchor.y1 + anchor.y2 - height + 1) / 2)
    elseif placement == 'right' then
        left = anchor.x2 + target_gap + 1
        top = math.floor((anchor.y1 + anchor.y2 - height + 1) / 2)
    elseif placement == 'above' then
        left = math.floor((anchor.x1 + anchor.x2 - width + 1) / 2)
        top = anchor.y1 - target_gap - height
    else
        left = math.floor((anchor.x1 + anchor.x2 - width + 1) / 2)
        top = anchor.y2 + target_gap + 1
    end
    return {x1=left, y1=top, x2=left + width - 1, y2=top + height - 1}
end

---Returns the gap cells directly connecting a target anchor and rail surface.
---@param placement string
---@param anchor table
---@param surface_bounds table
---@param target_gap integer
---@return table|nil
local function retention_bridge(placement, anchor, surface_bounds, target_gap)
    if target_gap == 0 then return nil end
    local bridge
    if placement == 'left' or placement == 'right' then
        local y1 = math.max(anchor.y1, surface_bounds.y1)
        local y2 = math.min(anchor.y2, surface_bounds.y2)
        if y1 > y2 then return nil end
        bridge = placement == 'left' and {
            x1=surface_bounds.x2 + 1, x2=anchor.x1 - 1, y1=y1, y2=y2,
        } or {
            x1=anchor.x2 + 1, x2=surface_bounds.x1 - 1, y1=y1, y2=y2,
        }
    else
        local x1 = math.max(anchor.x1, surface_bounds.x1)
        local x2 = math.min(anchor.x2, surface_bounds.x2)
        if x1 > x2 then return nil end
        bridge = placement == 'above' and {
            x1=x1, x2=x2, y1=surface_bounds.y2 + 1, y2=anchor.y1 - 1,
        } or {
            x1=x1, x2=x2, y1=anchor.y2 + 1, y2=surface_bounds.y1 - 1,
        }
    end
    return bridge.x1 <= bridge.x2 and bridge.y1 <= bridge.y2 and bridge or nil
end

---@class dwarfui.HoverActionRailSurface: widgets.Panel
---@field super widgets.Panel
---@field ATTRS table
local HoverActionRailSurface = defclass(nil, widgets.Panel)
HoverActionRailSurface.ATTRS{
    frame={l=0, t=0, w=1, h=1},
    frame_background=false,
    frame_style=false,
    frame_inset=0,
    visible=false,
}

---Paints background first, frame second, and leaves action painting to Panel.
---@param dc gui.Painter
---@param rect gui.ViewRect
function HoverActionRailSurface:onRenderFrame(dc, rect)
    if self.frame_background then dc:fill(rect, self.frame_background) end
    if self.frame_style then gui.paint_frame(dc, rect, self.frame_style) end
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
---@field target_gap integer Cells between the target anchor and the outer rail surface.
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
---@field retention_bridge table|nil Gap cells connecting the target and rail.
---@overload fun(init_table: dwarfui.HoverActionRail.attrs): self
HoverActionRail = defclass(HoverActionRail, widgets.Widget)
HoverActionRail.ATTRS{
    frame={l=0, t=0, r=0, b=0},
    actions=DEFAULT_NIL,
    target_at=DEFAULT_NIL,
    validate_target=DEFAULT_NIL,
    context_active=DEFAULT_NIL,
    mouse_provider=DEFAULT_NIL,
    placement_bounds_provider=DEFAULT_NIL,
    placement_order={'left', 'right', 'above', 'below'},
    action_gap=0,
    target_gap=0,
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
    assert(is_nonnegative_integer(self.target_gap),
        'HoverActionRail.target_gap must be a nonnegative integer')
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
        widget.visible = false
        widget.enabled = false
        table.insert(self.action_widgets, widget)
    end
    self.surface = HoverActionRailSurface{}
    self.surface:addviews(self.action_widgets)
    self:addviews{self.surface}
    self.active_target = nil
    self.rail_bounds = nil
    self.retention_bridge = nil
end

---Returns the currently retained target without refreshing its validity.
---@return dwarfui.HoverActionTarget|nil
function HoverActionRail:get_target()
    return self.active_target
end

---Returns whether a local point lies in an inclusive rectangle.
---@param rectangle table|nil
---@param x integer|nil
---@param y integer|nil
---@return boolean
local function contains_point(rectangle, x, y)
    return rectangle and x ~= nil and y ~= nil and x >= rectangle.x1 and
        x <= rectangle.x2 and y >= rectangle.y1 and y <= rectangle.y2
end

---Clears presentation, geometry, and retained-target state.
function HoverActionRail:clear()
    self.active_target = nil
    self.retention_bridge = nil
    self.rail_bounds = nil
    self.placement = nil
    self.visible_actions = nil
    self.content_width = nil
    self.content_height = nil
    self.surface.visible = false
    for _, widget in ipairs(self.action_widgets) do
        widget.visible = false
        widget.enabled = false
    end
end

---Binds a fresh target snapshot and updates its rendered surface.
---@param target dwarfui.HoverActionTarget
function HoverActionRail:bind_target(target)
    assert(is_instance_of(target, HoverActionTarget),
        'HoverActionRail.bind_target requires a HoverActionTarget')
    self.active_target = target
    self:refresh_surface()
end

---Updates the current target from context, pointer, and retained-region state.
---@return boolean changed
function HoverActionRail:update_hover()
    if not self.context_active() then
        local changed = self.active_target ~= nil
        self:clear()
        return changed
    end
    local x, y = self:get_local_pointer()
    local resolved = self:resolve_target_at_pointer(x, y)
    if resolved then
        local changed = not self.active_target or self.active_target.key ~= resolved.key
        self:bind_target(resolved)
        return changed
    end
    local retained = self.active_target
    if not retained then return false end
    local fresh = self.validate_target(retained)
    assert(fresh == nil or is_instance_of(fresh, HoverActionTarget),
        'HoverActionRail.validate_target must return a HoverActionTarget or nil')
    if not fresh or fresh.key ~= retained.key then
        self:clear()
        return true
    end
    self:bind_target(fresh)
    if contains_point(fresh.anchor, x, y) or
            contains_point(self.rail_bounds, x, y) or
            contains_point(self.retention_bridge, x, y) then
        return false
    end
    self:clear()
    return true
end

---Converts the current screen pointer cell into this rail's local coordinates.
---@return integer|nil x
---@return integer|nil y
function HoverActionRail:get_local_pointer()
    local screen_x, screen_y = self.mouse_provider()
    if screen_x == nil or screen_y == nil or not self.frame_body then
        return nil, nil
    end
    return self.frame_body:localXY(screen_x, screen_y)
end

---Resolves one fresh target using supplied or current rail-local coordinates.
---@param x? integer
---@param y? integer
---@return dwarfui.HoverActionTarget|nil
function HoverActionRail:resolve_target_at_pointer(x, y)
    if x == nil or y == nil then x, y = self:get_local_pointer() end
    if x == nil or y == nil then return nil end
    local target = self.target_at(x, y)
    assert(target == nil or is_instance_of(target, HoverActionTarget),
        'HoverActionRail.target_at must return a HoverActionTarget or nil')
    return target
end

---Places visible action widgets within the current surface body.
---@param placement string
function HoverActionRail:layout_actions(placement)
    local cursor = placement == 'left' and self.content_width or 0
    for _, item in ipairs(self.visible_actions) do
        if placement == 'left' then
            cursor = cursor - item.width
            item.widget.frame = placed_frame(item.widget.frame, cursor,
                math.floor((self.content_height - item.height) / 2),
                item.width, item.height)
            cursor = cursor - item.action.gap_after - self.action_gap
        else
            item.widget.frame = placed_frame(item.widget.frame, cursor,
                math.floor((self.content_height - item.height) / 2),
                item.width, item.height)
            cursor = cursor + item.width + item.action.gap_after +
                self.action_gap
        end
    end
end

---Recomputes the rail placement and its complete outer ownership rectangle.
---@return boolean placed
function HoverActionRail:refresh_placement()
    if not self.active_target or not self.content_width then return false end
    local bounds = copy_bounds(self.placement_bounds_provider())
    local width, height = self.surface.frame.w, self.surface.frame.h
    for _, placement in ipairs(self.placement_order) do
        local candidate = placement_rectangle(placement, self.active_target.anchor,
            width, height, self.target_gap)
        if fits_bounds(bounds, candidate) then
            self.surface.frame = placed_frame(self.surface.frame,
                candidate.x1, candidate.y1, width, height)
            self:layout_actions(placement)
            self.surface.visible = true
            self.rail_bounds = candidate
            self.retention_bridge = retention_bridge(placement,
                self.active_target.anchor, candidate, self.target_gap)
            self.placement = placement
            return true
        end
    end
    self.surface.visible = false
    self.rail_bounds = nil
    self.retention_bridge = nil
    self.placement = nil
    return false
end

---Recomputes presentation and body-relative action frames for the current target.
---
---Hover ownership assigns `active_target` in a later lifecycle layer. Keeping
---the presentation refresh separate lets that layer update a target without
---recreating any action widgets.
function HoverActionRail:refresh_surface()
    local target = self.active_target
    if not target then
        self.surface.visible = false
        self.rail_bounds = nil
        self.retention_bridge = nil
        self.visible_actions = nil
        self.content_width = nil
        self.content_height = nil
        for _, widget in ipairs(self.action_widgets) do
            widget.visible = false
            widget.enabled = false
        end
        return
    end

    local background = resolve_presentation_value(self.background_pen, target)
    local border = resolve_presentation_value(self.border_style, target)
    validate_resolved_presentation_value(background,
        'HoverActionRail.background_pen')
    validate_resolved_presentation_value(border,
        'HoverActionRail.border_style')
    self.surface.frame_background = parse_background(background)
    self.surface.frame_style = border
    self.surface.frame_inset = self.content_inset

    local content_width, content_height, last_gap_after = 0, 0, 0
    self.visible_actions = {}
    for index, action in ipairs(self.actions) do
        local widget = self.action_widgets[index]
        local visible = action.visible(target)
        assert(type(visible) == 'boolean',
            'HoverAction.visible must return a boolean')
        local enabled = action.enabled(target)
        assert(type(enabled) == 'boolean',
            'HoverAction.enabled must return a boolean')
        widget.visible = visible
        widget.enabled = visible and enabled
        if widget.visible then
            local frame = widget.frame or {}
            local width = frame.w or 1
            local height = frame.h or 1
            assert(is_nonnegative_integer(width) and width > 0,
                'HoverAction widget frame width must be a positive integer')
            assert(is_nonnegative_integer(height) and height > 0,
                'HoverAction widget frame height must be a positive integer')
            table.insert(self.visible_actions, {
                action=action,
                widget=widget,
                width=width,
                height=height,
            })
            content_width = content_width + width + action.gap_after +
                self.action_gap
            content_height = math.max(content_height, height)
            last_gap_after = action.gap_after
        end
    end

    if content_width == 0 then
        self.surface.visible = false
        self.rail_bounds = nil
        self.retention_bridge = nil
        self.content_width = nil
        self.content_height = nil
        return
    end
    content_width = content_width - self.action_gap - last_gap_after
    self.content_width = content_width
    self.content_height = content_height
    local inset_left, inset_top, inset_right, inset_bottom = inset_edges(
        self.content_inset)
    local border_extent = self.surface.frame_style and 1 or 0
    self.surface.frame = placed_frame(self.surface.frame, 0, 0,
        content_width + inset_left + inset_right + 2 * border_extent,
        content_height + inset_top + inset_bottom + 2 * border_extent)
    self:refresh_placement()
end

---Refreshes local placement before forwarding a parent layout change.
---@param parent_rect gui.ViewRect|nil
function HoverActionRail:updateLayout(parent_rect)
    if self.active_target then self:refresh_surface() end
    HoverActionRail.super.updateLayout(self, parent_rect)
end

---Refreshes hover state before drawing the current surface and action widgets.
---@param dc gui.Painter
function HoverActionRail:render(dc)
    local changed = self:update_hover()
    if changed and self.frame_parent_rect then
        self:updateLayout(self.frame_parent_rect)
    end
    HoverActionRail.super.render(self, dc)
end

---Revalidates and invokes one action against the current target snapshot.
---@param action dwarfui.HoverAction
---@return boolean activated
function HoverActionRail:activate(action)
    assert(is_instance_of(action, HoverAction),
        'HoverActionRail.activate requires a HoverAction')
    local target = self.active_target
    if not target then return false end
    local fresh = self.validate_target(target)
    if not fresh or not is_instance_of(fresh, HoverActionTarget) or
            fresh.key ~= target.key then
        self:clear()
        return false
    end
    self:bind_target(fresh)
    if not action.visible(fresh) or not action.enabled(fresh) then return false end
    return action.activate(fresh) ~= false
end

---Consumes input owned by the visible rail while passing unrelated input through.
---@param keys table|nil
---@return boolean
function HoverActionRail:onInput(keys)
    self:update_hover()
    if not self.surface.visible then return false end
    local x, y = self:get_local_pointer()
    if not contains_point(self.rail_bounds, x, y) then return false end
    if self.surface:inputToSubviews(keys or {}) then return true end
    local scroll = keys and (keys.CONTEXT_SCROLL_UP or keys.CONTEXT_SCROLL_DOWN or
        keys.STANDARDSCROLL_UP or keys.STANDARDSCROLL_DOWN or
        keys.CONTEXT_SCROLL_PAGEUP or keys.CONTEXT_SCROLL_PAGEDOWN or
        keys.STANDARDSCROLL_PAGEUP or keys.STANDARDSCROLL_PAGEDOWN)
    if scroll then return self.consume_scroll end
    return keys and keys._MOUSE_L or false
end
