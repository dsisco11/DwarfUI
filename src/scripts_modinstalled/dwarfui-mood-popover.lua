--@ module=true

-- Fortress-mode overlay for the native dwarf mood counters.

local overlay = require('plugins.overlay')
local MoodPopoverModel = reqscript('dwarfui/mood_popover').MoodPopoverModel
local Popover = reqscript('dwarfui/popover').Popover

---Reads the native top-panel hover instruction when fortress UI is available.
---@return any|nil
local function default_hover_provider()
    local interface = df.global.game and df.global.game.main_interface
    return interface and interface.current_hover or nil
end

---Reads the current screen-space mouse position.
---@return integer|nil x
---@return integer|nil y
local function default_mouse_provider()
    return dfhack.screen.getMousePos()
end

---Builds a fresh unit snapshot with the production mood model.
---@param descriptor table
---@return table[]
local function default_snapshot_provider(descriptor)
    return MoodPopoverModel{}:build_active_snapshot(descriptor)
end

---Returns whether the overlay still has an active fortress map to present in.
---@return boolean
local function default_active_provider()
    if df.global.world == nil then return false end
    local viewscreen = dfhack.gui.getDFViewscreen(true)
    return viewscreen ~= nil and
        dfhack.gui.matchFocusString('dwarfmode/Default', viewscreen)
end

---@class dwarfui.MoodPopoverOverlay: plugins.overlay.OverlayWidget
---@field selected_descriptor table|nil
---@field popover dwarfui.Popover
---@field refresh_ticks integer
---@field mood_model dwarfui.MoodPopoverModel
---@field hover_provider fun(): any|nil
---@field mouse_provider fun(): integer|nil, integer|nil
---@field snapshot_provider fun(descriptor: table): table[]
---@field active_provider fun(): boolean
MoodPopoverOverlay = defclass(MoodPopoverOverlay, overlay.OverlayWidget)
MoodPopoverOverlay.ATTRS{
    desc='Shows the citizens represented by a hovered fortress mood icon.',
    version='4',
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
    snapshot_provider=default_snapshot_provider,
    active_provider=default_active_provider,
}

---Constructs the fullscreen transparent host and its reusable popover.
function MoodPopoverOverlay:init()
    self.selected_descriptor = nil
    self.refresh_ticks = 0
    self.mood_model = MoodPopoverModel{}
    self.popover = Popover{view_id='mood_popover'}
    -- DFHack invokes this lifecycle callback without an instance argument.
    self.overlay_ondisable = function() self:clear() end
    self:addviews{self.popover}
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

---Samples native hover and pointer state, then applies the retention rules.
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

    local descriptor = self.mood_model:resolve_hover(self.hover_provider())
    if descriptor then
        if not self.selected_descriptor or
                descriptor.hover_value ~= self.selected_descriptor.hover_value then
            self:select(descriptor, mouse_x, mouse_y)
            return
        end
        self.refresh_ticks = self.refresh_ticks + 1
        if self.refresh_ticks >= self.refresh_interval then
            self.refresh_ticks = 0
            self:refresh()
        end
        return
    end

    if not self.popover:contains_point(mouse_x, mouse_y) then self:clear() end
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

---Passes input through except for popover wheel scrolling inside its list.
---@param keys table
---@return boolean|nil
function MoodPopoverOverlay:onInput(keys)
    return self.popover:onInput(keys)
end

OVERLAY_WIDGETS = {
    mood_popover=MoodPopoverOverlay,
}
