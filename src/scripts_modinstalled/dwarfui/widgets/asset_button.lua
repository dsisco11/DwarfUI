--@ module=true

local utils = require('utils')
local widgets = require('gui.widgets')
reqscript('dwarfui/widget_extensions')

local getval = utils.getval

---Returns whether a value is an integer.
---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == 'number' and value % 1 == 0
end

---Returns the number of single-byte cells in one classic graphics row.
---@param row string|string[]
---@param field_name string
---@param row_index integer
---@return integer
local function validate_row(row, field_name, row_index)
    local row_type = type(row)
    assert(row_type == 'string' or row_type == 'table',
        ('%s row %d must be a string or character table'):format(
            field_name, row_index))

    local width = #row
    if row_type == 'table' then
        local cell_count = 0
        width = 0
        for column in pairs(row) do
            assert(is_integer(column) and column > 0,
                ('%s row %d has a non-sequential cell index'):format(
                    field_name, row_index))
            width = math.max(width, column)
            cell_count = cell_count + 1
        end
        assert(cell_count == width,
            ('%s row %d must contain contiguous cells'):format(
                field_name, row_index))
    end
    assert(width > 0,
        ('%s row %d must not be empty'):format(field_name, row_index))
    if row_type == 'table' then
        for column=1,width do
            local character = row[column]
            assert(type(character) == 'string' and #character == 1,
                ('%s cell %d,%d must be one byte'):format(
                    field_name, column, row_index))
        end
    end
    return width
end

---Validates a rectangular classic graphics grid.
---@param grid (string|string[])[]
---@param field_name string
---@param expected_width? integer
---@param expected_height? integer
---@return integer width
---@return integer height
local function validate_grid(
        grid, field_name, expected_width, expected_height)
    assert(type(grid) == 'table' and #grid > 0,
        field_name .. ' must be a non-empty row table')

    local height = #grid
    local width = validate_row(grid[1], field_name, 1)
    for row_index=2,height do
        local row_width = validate_row(grid[row_index], field_name, row_index)
        assert(row_width == width,
            ('%s row %d has width %d; expected %d'):format(
                field_name, row_index, row_width, width))
    end
    if expected_width then
        assert(width == expected_width,
            ('%s has width %d; expected %d'):format(
                field_name, width, expected_width))
    end
    if expected_height then
        assert(height == expected_height,
            ('%s has height %d; expected %d'):format(
                field_name, height, expected_height))
    end
    return width, height
end

---Validates a DFHack interface asset origin.
---@param asset {page: string, x: integer, y: integer}|nil
---@param field_name string
local function validate_asset(asset, field_name)
    if asset == nil then return end
    assert(type(asset) == 'table',
        field_name .. ' must be an interface asset table')
    assert(type(asset.page) == 'string' and asset.page ~= '',
        field_name .. '.page must be a non-empty string')
    assert(is_integer(asset.x),
        field_name .. '.x must be an integer')
    assert(is_integer(asset.y),
        field_name .. '.y must be an integer')
end

---Returns a shallow copy so button instances never share a frame table.
---@param source table|nil
---@return table
local function copy_frame(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

---@class dwarfui.AssetButton.attrs: widgets.Label.attrs
---@field asset? {page: string, x: integer, y: integer}
---@field asset_hover? {page: string, x: integer, y: integer}
---@field chars (string|string[])[]
---@field chars_hover? (string|string[])[]
---@field pens? dfhack.color|dfhack.pen|(dfhack.color|dfhack.pen)[][]
---@field pens_hover? dfhack.color|dfhack.pen|(dfhack.color|dfhack.pen)[][]
---@field visible? boolean|fun(): boolean
---@field enabled? boolean|fun(): boolean
---@field disabled? boolean|fun(): boolean
---@field tooltip? string
---@field on_activate fun()

---@class dwarfui.AssetButton.attrs.partial: dwarfui.AssetButton.attrs

---@class dwarfui.AssetButton: widgets.Label, dwarfui.AssetButton.attrs
---@field super widgets.Label
---@field ATTRS dwarfui.AssetButton.attrs|fun(attributes: dwarfui.AssetButton.attrs.partial)
---@overload fun(init_table: dwarfui.AssetButton.attrs.partial): self
AssetButton = defclass(AssetButton, widgets.Label)
AssetButton.ATTRS{
    asset=DEFAULT_NIL,
    asset_hover=DEFAULT_NIL,
    chars=DEFAULT_NIL,
    chars_hover=DEFAULT_NIL,
    pens=DEFAULT_NIL,
    pens_hover=DEFAULT_NIL,
    on_activate=DEFAULT_NIL,
    auto_height=false,
}

---Validates the declared asset and builds its DFHack label cells.
function AssetButton:init()
    assert(type(self.on_activate) == 'function',
        'AssetButton.on_activate must be a function')
    local width, height = validate_grid(self.chars, 'AssetButton.chars')
    if self.chars_hover then
        validate_grid(self.chars_hover, 'AssetButton.chars_hover',
            width, height)
    end
    validate_asset(self.asset, 'AssetButton.asset')
    validate_asset(self.asset_hover, 'AssetButton.asset_hover')
    assert(not self.asset_hover or self.asset,
        'AssetButton.asset_hover requires AssetButton.asset')

    local frame = copy_frame(self.frame)
    if frame.w ~= nil then
        assert(frame.w == width,
            ('AssetButton frame width is %s; expected %d'):format(
                tostring(frame.w), width))
    end
    if frame.h ~= nil then
        assert(frame.h == height,
            ('AssetButton frame height is %s; expected %d'):format(
                tostring(frame.h), height))
    end
    frame.w = width
    frame.h = height
    self.frame = frame

    self:setText(widgets.Label.makeButtonLabelText{
        asset=self.asset,
        asset_hover=self.asset_hover,
        chars=self.chars,
        chars_hover=self.chars_hover,
        pens=self.pens,
        pens_hover=self.pens_hover,
    })
end

---Returns whether the button is currently visible and enabled.
---@return boolean
function AssetButton:is_interactive()
    if self.visible ~= nil and not getval(self.visible) then return false end
    if self.disabled ~= nil and getval(self.disabled) then return false end
    if self.enabled ~= nil and not getval(self.enabled) then return false end
    return true
end

---Returns whether the renderer should apply the complete hover-cell grid.
---@return boolean
function AssetButton:shouldHover()
    return self:is_interactive()
end

---Invokes the configured action when the button can currently interact.
---@return boolean activated
function AssetButton:activate()
    if not self:is_interactive() then return false end
    self.on_activate()
    return true
end

---Consumes only a left click that lands inside an interactive button.
---@param keys table|nil
---@return boolean
function AssetButton:onInput(keys)
    if not keys or not keys._MOUSE_L or not self:getMousePos() then
        return false
    end
    return self:activate()
end
