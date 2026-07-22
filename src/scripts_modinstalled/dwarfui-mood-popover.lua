--@ module=true

-- Fortress-mode overlay for the native dwarf mood counters.

local overlay = require('plugins.overlay')
local mood_model = reqscript('dwarfui/mood_popover')
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
    return mood_model.build_active_snapshot(descriptor)
end

---Returns whether the overlay still has an active fortress map to present in.
---@return boolean
local function default_active_provider()
    if df.global.world == nil then return false end
    local gui = dfhack.gui
    return not gui or not gui.getCurFocus or
        gui.getCurFocus(true) == 'dwarfmode/Default'
end

---@class dwarfui.MoodPopoverOverlay: plugins.overlay.OverlayWidget
---@field selected_descriptor table|nil
---@field popover dwarfui.Popover
---@field refresh_ticks integer
---@field hover_provider fun(): any|nil
---@field mouse_provider fun(): integer|nil, integer|nil
---@field snapshot_provider fun(descriptor: table): table[]
---@field active_provider fun(): boolean
MoodPopoverOverlay = defclass(MoodPopoverOverlay, overlay.OverlayWidget)
MoodPopoverOverlay.ATTRS{
    default_enabled=true,
    viewscreens='dwarfmode/Default',
    fullscreen=true,
    frame={l=0, t=0, w=1, h=1},
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
    self.popover = Popover{view_id='mood_popover'}
    self:addviews{self.popover}
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

    local descriptor = mood_model.resolve_hover(self.hover_provider())
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

---Runs the inexpensive interactive hover sample for every overlay update.
function MoodPopoverOverlay:onUpdate()
    MoodPopoverOverlay.super.onUpdate(self)
    if not self.active_provider() then
        self:clear()
    elseif self.frame_parent_rect then
        self:update_popover()
    end
end

---Passes input through except for popover wheel scrolling inside its list.
---@param keys table
---@return boolean|nil
function MoodPopoverOverlay:onInput(keys)
    return self.popover:onInput(keys)
end

---Drops all retained state when DFHack disables the overlay.
function MoodPopoverOverlay:overlay_ondisable()
    self:clear()
end

OVERLAY_WIDGETS = {
    ['dwarfui-mood-popover']=MoodPopoverOverlay,
}

return {
    MoodPopoverOverlay=MoodPopoverOverlay,
}
