--@ module=true

-- Fortress-mode overlay for the native dwarf mood counters.

local overlay = require('plugins.overlay')
local gui = require('gui')
local MoodPopoverModel = reqscript('dwarfui/mood_popover').MoodPopoverModel
local Popover = reqscript('dwarfui/popover').Popover

---Reads the current screen-space mouse position.
---@return integer|nil x
---@return integer|nil y
local function default_mouse_provider()
    return dfhack.screen.getMousePos()
end

---Builds a fresh stress-ordered unit snapshot with the production mood model.
---@param descriptor table
---@return table[]
local function default_snapshot_provider(descriptor)
    return MoodPopoverModel{}:build_active_snapshot(descriptor)
end

---@class dwarfui.TopBarMoodDisplay: dfhack.class
---@field layout_width integer|nil
---@field layout_height integer|nil
---@field mood_rects table[]|nil
TopBarMoodDisplay = defclass(TopBarMoodDisplay)
TopBarMoodDisplay.ATTRS{
    read_tile=dfhack.screen.readTile,
    dimensions_provider=function()
        return df.global.gps.dimx, df.global.gps.dimy
    end,
    hover_instructions=df.main_hover_instruction,
}

---Clears the cached top information-bar layout.
function TopBarMoodDisplay:clear_layout()
    self.layout_width = nil
    self.layout_height = nil
    self.mood_rects = nil
end

---Returns whether a screen cell contains the expected ASCII character.
---@param x integer
---@param y integer
---@param expected integer
---@return boolean
function TopBarMoodDisplay:has_character(x, y, expected)
    local tile = self.read_tile(x, y)
    return tile ~= nil and tile.ch == expected
end

---Returns whether a two-by-two native mood icon occupies this location.
---@param x integer
---@param y integer
---@return boolean
function TopBarMoodDisplay:has_mood_icon(x, y)
    local separator = self.read_tile(x - 1, y)
    if separator == nil then return false end
    for icon_y=y,y + 1 do
        for icon_x=x,x + 1 do
            local tile = self.read_tile(icon_x, icon_y)
            if tile == nil or tile.ch ~= 0 or tile.tile == separator.tile then
                return false
            end
        end
    end
    return true
end

---Discovers the seven rendered mood-icon rectangles beside the Pop heading.
---@return table[]|nil
function TopBarMoodDisplay:find_layout()
    local width, height = self.dimensions_provider()
    if width == self.layout_width and height == self.layout_height and
            self.mood_rects ~= nil then
        return self.mood_rects
    end
    self:clear_layout()
    if width == nil or height == nil or width < 25 or height < 3 then
        return nil
    end

    for y=0,math.min(4, height - 3) do
        for x=0,width - 22 do
            if self:has_character(x, y, string.byte('P')) and
                    self:has_character(x + 1, y, string.byte('o')) and
                    self:has_character(x + 2, y, string.byte('p')) then
                local rects = {}
                local valid = true
                for hover_index=0,6 do
                    local icon_x = x + 4 + hover_index * 3
                    if not self:has_mood_icon(icon_x, y) then
                        valid = false
                        break
                    end
                    table.insert(rects, {
                        x1=icon_x,
                        y1=y,
                        x2=icon_x + 1,
                        y2=y + 2,
                        hover_index=hover_index,
                    })
                end
                if valid then
                    self.layout_width = width
                    self.layout_height = height
                    self.mood_rects = rects
                    return rects
                end
            end
        end
    end
    return nil
end

---Finds the top-bar mood column containing a screen-space pointer.
---@param mouse_x integer|nil
---@param mouse_y integer|nil
---@return table|nil
function TopBarMoodDisplay:find_hovered_rect(mouse_x, mouse_y)
    if mouse_x == nil or mouse_y == nil then return nil end
    for _, rect in ipairs(self:find_layout() or {}) do
        if mouse_x >= rect.x1 and mouse_x <= rect.x2 and
                mouse_y >= rect.y1 and mouse_y <= rect.y2 then
            return rect
        end
    end
    return nil
end

---Maps a pointer over the rendered top-bar mood icons to a mood instruction.
---@param mouse_x integer|nil
---@param mouse_y integer|nil
---@return any|nil
function TopBarMoodDisplay:resolve_hover(mouse_x, mouse_y)
    local rect = self:find_hovered_rect(mouse_x, mouse_y)
    return rect and self.hover_instructions[
        'INFO_STRESSED_' .. rect.hover_index] or nil
end

---Anchors a popout below the information bar at the hovered mood column.
---@param mouse_x integer
---@param mouse_y integer
---@return integer
---@return integer
function TopBarMoodDisplay:get_popover_anchor(mouse_x, mouse_y)
    local rect = self:find_hovered_rect(mouse_x, mouse_y)
    if rect then return rect.x1, rect.y2 + 1 end
    return mouse_x, mouse_y
end

local topbar_mood_display = TopBarMoodDisplay{}

---Resolves the pointer against DF's rendered top information-bar mood icons.
---@param mouse_x integer|nil
---@param mouse_y integer|nil
---@return any|nil
local function default_hover_provider(mouse_x, mouse_y)
    return topbar_mood_display:resolve_hover(mouse_x, mouse_y)
end

---Returns the stable mood-column anchor along the information bar's bottom.
---@param mouse_x integer
---@param mouse_y integer
---@return integer
---@return integer
local function default_anchor_provider(mouse_x, mouse_y)
    return topbar_mood_display:get_popover_anchor(mouse_x, mouse_y)
end

---Returns whether the fortress top information bar is currently visible.
---@return boolean
local function default_active_provider()
    if df.global.world == nil then return false end
    local viewscreen = dfhack.gui.getDFViewscreen(true)
    return viewscreen ~= nil and
        dfhack.gui.matchFocusString('dwarfmode/Default', viewscreen)
end

---Centers the map and initializes DF's native unit information card state.
---@param unit df.unit
---@return boolean
local function default_unit_opener(unit)
    if not unit or not df.isvalid(unit) then return false end
    local pos = xyz2pos(dfhack.units.getPosition(unit))
    if not dfhack.gui.revealInDwarfmodeMap(pos, true, true) then return false end

    local sheets = df.global.game.main_interface.view_sheets
    df.global.game.main_interface.view.have_calced_info = false
    sheets.context = df.view_sheets_context_type.REGULAR_PLAY
    sheets.active_sheet = df.view_sheet_type.UNIT
    sheets.active_id = unit.id
    sheets.viewing_unid:resize(0)
    sheets.viewing_unid:insert('#', unit.id)
    sheets.viewing_x = pos.x
    sheets.viewing_y = pos.y
    sheets.viewing_z = pos.z
    sheets.scroll_position = 0
    sheets.active_sub_tab = 0
    sheets.last_tick_update = -1
    sheets.open = true
    return true
end

---@class dwarfui.MoodPopoverOverlay: plugins.overlay.OverlayWidget
---@field selected_descriptor table|nil
---@field popover dwarfui.Popover
---@field refresh_ticks integer
---@field mood_model dwarfui.MoodPopoverModel
---@field hover_provider fun(mouse_x: integer, mouse_y: integer): any|nil
---@field mouse_provider fun(): integer|nil, integer|nil
---@field anchor_provider fun(mouse_x: integer, mouse_y: integer): integer, integer
---@field snapshot_provider fun(descriptor: table): table[]
---@field active_provider fun(): boolean
---@field unit_opener fun(unit: df.unit): boolean
MoodPopoverOverlay = defclass(MoodPopoverOverlay, overlay.OverlayWidget)
MoodPopoverOverlay.ATTRS{
    desc='Shows the citizens represented by a hovered fortress mood icon.',
    version='6',
    default_enabled=true,
    default_pos={x=1, y=1},
    viewscreens='dwarfmode/Default',
    hotspot=true,
    fullscreen=true,
    frame={l=0, t=0, w=1, h=1},
    overlay_onupdate_max_freq_seconds=0,
    refresh_interval=10,
    hover_provider=default_hover_provider,
    mouse_provider=default_mouse_provider,
    anchor_provider=default_anchor_provider,
    snapshot_provider=default_snapshot_provider,
    active_provider=default_active_provider,
    unit_opener=default_unit_opener,
}

---Constructs the fullscreen host and its stable-scroll interactive popover.
function MoodPopoverOverlay:init()
    self.selected_descriptor = nil
    self.refresh_ticks = 0
    self.mood_model = MoodPopoverModel{}
    self.popover = Popover{
        view_id='mood_popover',
        frame_style=gui.FRAME_INTERIOR,
        on_submit=function(row) return self:open_row(row) end,
    }
    -- DFHack invokes this lifecycle callback without an instance argument.
    self.overlay_ondisable = function() self:clear() end
    self:addviews{self.popover}
end

---Opens the native unit card for a selected popover row.
---@param row table|nil
---@return boolean|nil
function MoodPopoverOverlay:open_row(row)
    if not row or not row.unit then return end
    if not self.unit_opener(row.unit) then return false end
    self:clear()
    return true
end

---Expands the transparent overlay host across the current screen.
---@param parent_rect gui.ViewRect
function MoodPopoverOverlay:preUpdateLayout(parent_rect)
    self.frame.w = parent_rect.width
    self.frame.h = parent_rect.height
end

---Clears the selected mood and all snapshot rows retained by the overlay.
function MoodPopoverOverlay:clear()
    self.selected_descriptor = nil
    self.refresh_ticks = 0
    self.popover:set_content('', {})
    self.popover:hide()
end

---Shows a newly selected native mood at its fixed pointer anchor.
---@param descriptor table
---@param mouse_x integer
---@param mouse_y integer
function MoodPopoverOverlay:select(descriptor, mouse_x, mouse_y)
    self.selected_descriptor = descriptor
    self.refresh_ticks = 0
    self.popover:set_content(descriptor.label,
        self.snapshot_provider(descriptor), true)
    self.popover:show_at(mouse_x, mouse_y, self.frame_parent_rect)
end

---Refreshes the visible rows without changing selection, anchor, or scroll.
function MoodPopoverOverlay:refresh()
    if not self.selected_descriptor then return end
    self.popover:set_content(self.selected_descriptor.label,
        self.snapshot_provider(self.selected_descriptor), false)
end

---Samples top-bar hover and pointer state, then applies the retention rules.
function MoodPopoverOverlay:update_popover()
    if not self.active_provider() then
        self:clear()
        return
    end

    local mouse_x, mouse_y = self.mouse_provider()
    if mouse_x == nil or mouse_y == nil then
        self:clear()
        return
    end

    local descriptor = self.mood_model:resolve_hover(
        self.hover_provider(mouse_x, mouse_y))
    if descriptor then
        if not self.selected_descriptor or
                descriptor.hover_value ~= self.selected_descriptor.hover_value then
            local anchor_x, anchor_y = self.anchor_provider(mouse_x, mouse_y)
            self:select(descriptor, anchor_x, anchor_y)
            return
        end
        self.refresh_ticks = self.refresh_ticks + 1
        if self.refresh_ticks >= self.refresh_interval then
            self.refresh_ticks = 0
            self:refresh()
        end
        return
    end

    if not self.popover:contains_retention_point(mouse_x, mouse_y) then
        self:clear()
    end
end

---Clears retained state when the fortress screen is no longer active.
function MoodPopoverOverlay:overlay_onupdate()
    if not self.active_provider() then self:clear() end
end

---Samples render-time native hover state and draws the current popover.
---@param dc gui.Painter
function MoodPopoverOverlay:render(dc)
    if self.frame_parent_rect then self:update_popover() end
    MoodPopoverOverlay.super.render(self, dc)
end

---Consumes context-wheel scrolling while open and passes other input through.
---@param keys table
---@return boolean|nil
function MoodPopoverOverlay:onInput(keys)
    return self.popover:onInput(keys)
end

OVERLAY_WIDGETS = {
    mood_popover=MoodPopoverOverlay,
}
