--@ module=true

-- Fortress-mode overlay that paints corner hotkey labels on native UI buttons.

local overlay = require('plugins.overlay')
local hotkeys = reqscript('dwarfui/ui_hotkeys')

---@class dwarfui.UiMenuHotkeysOverlay: plugins.overlay.OverlayWidget
---@field model dwarfui.UiHotkeyModel
---@field model_builder fun(): dwarfui.UiHotkeyModel
---@field latest_snapshot dwarfui.UiHotkeySnapshot
UiMenuHotkeysOverlay = defclass(UiMenuHotkeysOverlay, overlay.OverlayWidget)
UiMenuHotkeysOverlay.ATTRS{
    desc='Shows active hotkey labels on the fortress bottom menu buttons.',
    version='1',
    default_enabled=true,
    default_pos={x=1, y=1},
    viewscreens='dwarfmode/Default',
    hotspot=true,
    fullscreen=false,
    full_interface=true,
    frame={l=0, t=0, w=1, h=1},
    overlay_onupdate_max_freq_seconds=0,
    label_pen=COLOR_WHITE,
    label_inset_x=0,
    label_inset_y=0,
    model_builder=function()
        return hotkeys.UiHotkeyModel{}
    end,
}

---Initializes the overlay-owned hotkey model and latest render snapshot.
function UiMenuHotkeysOverlay:init()
    assert(type(self.model_builder) == 'function',
        'UiMenuHotkeysOverlay.model_builder must be a function')
    self.model = self.model_builder()
    assert(type(self.model) == 'table' and
            type(self.model.build_snapshot) == 'function',
        'UiMenuHotkeysOverlay.model must support build_snapshot()')
    self.latest_snapshot = {
        active=false, layout_signature='init', buttons={}, bounds=nil,
    }
end

---Fits the transparent host to the native button group currently being labeled.
---@param parent_rect gui.ViewRect
function UiMenuHotkeysOverlay:preUpdateLayout(parent_rect)
    self:sync_snapshot()
    self:apply_snapshot_frame(parent_rect)
end

---Refreshes the most recent model snapshot.
function UiMenuHotkeysOverlay:sync_snapshot()
    self.latest_snapshot = self.model:build_snapshot()
end

---Updates the overlay frame from the resolved native screen-space bounds.
---@param parent_rect gui.ViewRect|nil
---@return boolean changed
function UiMenuHotkeysOverlay:apply_snapshot_frame(parent_rect)
    local bounds = self.latest_snapshot and self.latest_snapshot.bounds or nil
    local l, t, w, h = 0, 0, 1, 1
    if bounds then
        l = bounds.x1 - (parent_rect and parent_rect.x1 or 0)
        t = bounds.y1 - (parent_rect and parent_rect.y1 or 0)
        w = bounds.x2 - bounds.x1 + 1
        h = bounds.y2 - bounds.y1 + 1
    end
    local changed = self.frame.l ~= l or self.frame.t ~= t or
        self.frame.w ~= w or self.frame.h ~= h
    self.frame.l, self.frame.t = l, t
    self.frame.w, self.frame.h = w, h
    return changed
end

---Returns the top-right corner text anchor for one bounds rectangle.
---@param bounds {x1: integer, y1: integer, x2: integer, y2: integer}
---@param label string
---@return integer
---@return integer
function UiMenuHotkeysOverlay:label_anchor(bounds, label)
    local x = bounds.x2 - (#label - 1) - self.label_inset_x
    local y = bounds.y1 + self.label_inset_y
    if x < bounds.x1 then x = bounds.x1 end
    if y > bounds.y2 then y = bounds.y2 end
    return x, y
end

---Paints one menu button hotkey label using its current sampled bounds.
---@param dc gui.Painter
---@param button dwarfui.UiHotkeyResolvedButton
function UiMenuHotkeysOverlay:render_button_label(dc, button)
    local bounds = button and button.bounds
    local label = button and button.label or nil
    if type(bounds) ~= 'table' or type(label) ~= 'string' or label == '' then
        return
    end
    local x, y = self:label_anchor(bounds, label)
    dc:seek(x, y):string(label, self.label_pen)
end

---Re-samples model state and renders the bounded overlay panel.
---@param dc gui.Painter
function UiMenuHotkeysOverlay:render(dc)
    self:sync_snapshot()
    self:apply_snapshot_frame(self.frame_parent_rect)
    UiMenuHotkeysOverlay.super.render(self, dc)
    if not self.latest_snapshot.active then return end
    for _, button in ipairs(self.latest_snapshot.buttons or {}) do
        self:render_button_label(dc, button)
    end
end

---Updates snapshots continuously so slight layout shifts are reflected quickly.
function UiMenuHotkeysOverlay:overlay_onupdate()
    self:sync_snapshot()
    if self:apply_snapshot_frame(self.frame_parent_rect) and
            self.frame_parent_rect then
        self:updateLayout()
    end
end

---Never consumes input so native button behavior remains unchanged.
---@param _keys table
---@return false
function UiMenuHotkeysOverlay:onInput(_keys)
    return false
end

OVERLAY_WIDGETS = {
    ui_hotkeys=UiMenuHotkeysOverlay,
}
