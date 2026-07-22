--@ module=true

local gui = require('gui')
local widgets = require('gui.widgets')

-- widgets.Window reserves one frame cell and one inset cell on every edge.
local FRAME_BODY_PADDING = 2

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function row_text(row)
    if type(row) == 'table' then
        return tostring(row.name or row.text or '')
    end
    return tostring(row or '')
end

local function parent_edges(parent_rect)
    return parent_rect.x1, parent_rect.y1,
        parent_rect.x1 + parent_rect.width - 1,
        parent_rect.y1 + parent_rect.height - 1
end

---@class dwarfui.Popover: gui.widgets.Window
---@field anchor_x integer|nil
---@field anchor_y integer|nil
---@field rows table[]
---@field scroll_top integer
---@field visible_rows integer
---@field frame_global table|nil
---@field on_submit false|fun(row: any, index: integer)
Popover = defclass(nil, widgets.Window)
Popover.ATTRS{
    frame={l=0, t=0, w=1, h=1},
    frame_style=gui.FRAME_INTERIOR,
    frame_inset=1,
    draggable=false,
    resizable=false,
    no_force_pause_badge=true,
    visible=false,
    active=true,
    min_width=20,
    max_width=50,
    max_rows=12,
    margin=1,
    empty_message='No entries',
    on_submit=false,
}

---Constructs the reusable heading, list, and empty-state controls.
function Popover:init()
    self.rows = {}
    self.title = ''
    self.scroll_top = 1
    self.visible_rows = 0
    self.header = widgets.Label{
        view_id='header',
        frame={l=0, t=0, r=0, h=1},
        text='',
    }
    self.list = widgets.List{
        view_id='list',
        frame={l=0, t=1, r=0, h=1},
        choices={},
        on_submit=function(index, choice)
            if self.on_submit and choice then
                return self.on_submit(choice.row, index)
            end
        end,
    }
    self.empty = widgets.Label{
        view_id='empty',
        frame={l=0, t=1, r=0, h=1},
        text=self.empty_message,
        visible=false,
    }
    self:addviews{self.header, self.list, self.empty}
end

---Calculates a clamped popover frame in screen-space coordinates.
---@param anchor_x integer
---@param anchor_y integer
---@param parent_rect gui.ViewRect
---@param width integer
---@param height integer
---@param margin integer
---@return table
function Popover.calculate_frame(anchor_x, anchor_y, parent_rect, width, height,
        margin)
    assert(parent_rect and parent_rect.width and parent_rect.height,
        'DwarfUI Popover requires a parent rectangle.')
    margin = margin or 0
    local left, top, right, bottom = parent_edges(parent_rect)
    local available_width = math.max(1, parent_rect.width - 2 * margin)
    local available_height = math.max(1, parent_rect.height - 2 * margin)
    width = clamp(width, 1, available_width)
    height = clamp(height, 1, available_height)

    local x = clamp(anchor_x, left + margin, right - margin - width + 1)
    local below_y = anchor_y + 1
    local y
    if below_y + height - 1 <= bottom - margin then
        y = below_y
    else
        y = anchor_y - height
    end
    y = clamp(y, top + margin, bottom - margin - height + 1)

    return {x=x, y=y, w=width, h=height}
end

---Measures the content width needed to render the current heading and rows.
---@return integer
function Popover:measure_width()
    local width = #self.header.text
    for _, row in ipairs(self.rows) do
        width = math.max(width, #row_text(row))
    end
    return clamp(width + 2 * FRAME_BODY_PADDING,
        self.min_width, self.max_width)
end

---Returns the number of list rows that fit inside the current popover frame.
---@return integer
function Popover:get_visible_row_count()
    return self.visible_rows
end

---Returns whether the current rows exceed the visible list region.
---@return boolean
function Popover:has_overflow()
    return #self.rows > self.visible_rows
end

---Resets the list to its first row.
function Popover:reset_scroll()
    self.scroll_top = 1
    self.list.page_top = 1
end

---Clamps the current scroll position to the available visible list region.
function Popover:clamp_scroll()
    local maximum = math.max(1, #self.rows - self.visible_rows + 1)
    self.scroll_top = clamp(self.scroll_top, 1, maximum)
    self.list.page_top = self.scroll_top
end

---Moves the visible list window by a number of rows.
---@param delta integer
---@return boolean changed
function Popover:scroll(delta)
    if not self:has_overflow() then return false end
    local previous = self.scroll_top
    self.scroll_top = self.scroll_top + delta
    self:clamp_scroll()
    if self.scroll_top ~= previous and self.invalidate then self:invalidate() end
    return self.scroll_top ~= previous
end

---Sets the popover heading and all current list rows.
---@param title string
---@param rows table[]|nil
---@param reset_scroll? boolean Set false when refreshing the same subject.
function Popover:set_content(title, rows, reset_scroll)
    self.title = tostring(title or '')
    self.rows = rows or {}
    self.header:setText(('%s (%d)'):format(self.title, #self.rows))
    local choices = {}
    for _, row in ipairs(self.rows) do
        table.insert(choices, {text=row_text(row), row=row})
    end
    self.list:setChoices(choices)
    self.empty.visible = #self.rows == 0
    self.list.visible = #self.rows > 0
    if reset_scroll ~= false then self:reset_scroll() end
    if self.visible and self.frame_parent_rect then
        self:reposition(self.frame_parent_rect)
    end
end

---Updates frame, subview sizes, and list bounds for the current anchor.
---@param parent_rect gui.ViewRect
function Popover:reposition(parent_rect)
    assert(self.anchor_x ~= nil and self.anchor_y ~= nil,
        'DwarfUI Popover cannot reposition before show_at().')
    local requested_rows = math.min(math.max(1, #self.rows), self.max_rows)
    local desired_height = 2 * FRAME_BODY_PADDING + 1 + requested_rows
    local frame = Popover.calculate_frame(self.anchor_x, self.anchor_y,
        parent_rect, self:measure_width(), desired_height, self.margin)
    self.visible_rows = math.min(#self.rows,
        math.max(0, frame.h - 2 * FRAME_BODY_PADDING - 1))
    self.frame_global = frame
    self.frame = {
        l=frame.x - parent_rect.x1,
        t=frame.y - parent_rect.y1,
        w=frame.w,
        h=frame.h,
    }
    self.header.frame = {l=0, t=0, r=0, h=1}
    self.list.frame = {l=0, t=1, r=0, h=math.max(1, self.visible_rows)}
    self.empty.frame = {l=0, t=1, r=0, h=1}
    self:clamp_scroll()
    self:updateLayout(parent_rect)
end

---Shows the popover at a fixed screen-space anchor.
---@param anchor_x integer
---@param anchor_y integer
---@param parent_rect gui.ViewRect
function Popover:show_at(anchor_x, anchor_y, parent_rect)
    assert(type(anchor_x) == 'number' and type(anchor_y) == 'number',
        'DwarfUI Popover anchor coordinates must be numbers.')
    self.anchor_x = anchor_x
    self.anchor_y = anchor_y
    self.visible = true
    self:reposition(parent_rect)
    if self.invalidate then self:invalidate() end
end

---Hides the popover and clears its visible hit region.
function Popover:hide()
    if not self.visible then return end
    self.visible = false
    self.frame_global = nil
    if self.invalidate then self:invalidate() end
end

---Tests whether a screen-space point lies inside the visible panel frame.
---@param x integer|nil
---@param y integer|nil
---@return boolean
function Popover:contains_point(x, y)
    local frame = self.frame_global
    return self.visible and frame and x ~= nil and y ~= nil and
        x >= frame.x and x < frame.x + frame.w and
        y >= frame.y and y < frame.y + frame.h
end

---Tests whether a point is inside the panel or its one-row approach bridge.
---@param x integer|nil
---@param y integer|nil
---@return boolean
function Popover:contains_retention_point(x, y)
    if self:contains_point(x, y) then return true end
    local frame = self.frame_global
    return self.visible and frame and x ~= nil and y ~= nil and
        x >= frame.x and x < frame.x + frame.w and y == frame.y - 1
end

---Tests whether a screen-space point lies inside the visible list rows.
---@param x integer|nil
---@param y integer|nil
---@return boolean
function Popover:contains_list_point(x, y)
    local frame = self.frame_global
    return self:contains_point(x, y) and #self.rows > 0 and
        x >= frame.x + FRAME_BODY_PADDING and
        x < frame.x + frame.w - FRAME_BODY_PADDING and
        y >= frame.y + FRAME_BODY_PADDING + 1 and
        y < frame.y + FRAME_BODY_PADDING + 1 + self.visible_rows
end

---Consumes standard wheel scrolling whenever an overflowing popover is open.
---
---The pointer can remain on the originating moodlet, avoiding a gap crossing
---between the top information bar and the popover.
---@param keys table
---@return boolean|nil
function Popover:onInput(keys)
    if not self.visible then return end
    local mouse_x, mouse_y = dfhack.screen.getMousePos()
    if keys._MOUSE_L and self:contains_list_point(mouse_x, mouse_y) then
        return self.list:onInput(keys)
    end
    if not self:has_overflow() then return end
    if keys.CONTEXT_SCROLL_UP or keys.STANDARDSCROLL_UP then
        self:scroll(-1)
        return true
    elseif keys.CONTEXT_SCROLL_DOWN or keys.STANDARDSCROLL_DOWN then
        self:scroll(1)
        return true
    elseif keys.CONTEXT_SCROLL_PAGEUP or keys.STANDARDSCROLL_PAGEUP then
        self:scroll(-math.max(1, self.visible_rows))
        return true
    elseif keys.CONTEXT_SCROLL_PAGEDOWN or keys.STANDARDSCROLL_PAGEDOWN then
        self:scroll(math.max(1, self.visible_rows))
        return true
    end
end
