--@ module=true

local overlay = require('plugins.overlay')
local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')
local geometry_module = reqscript('dwarfui/hotkeys/geometry')
local geometry = geometry_module.HotkeyGeometry or geometry_module

---@enum dwarfui.HotkeyLabelAnchor
HotkeyLabelAnchor = immutable_enum.define({
    TOP_LEFT=1,
    TOP_RIGHT=2,
    BOTTOM_LEFT=3,
    BOTTOM_RIGHT=4,
}, 'HotkeyLabelAnchor')

---@class dwarfui.HotkeyGroupOverlay: plugins.overlay.OverlayWidget
---@field model table
---@field model_builder fun(): dwarfui.HotkeyGroupModel
---@field latest_snapshot dwarfui.HotkeyGroupSnapshot
---@field label_anchor_kind dwarfui.HotkeyLabelAnchor
---@field label_pen any
---@field resolved_label_pen any
---@field label_inset_x integer
---@field label_inset_y integer
HotkeyGroupOverlay = defclass(HotkeyGroupOverlay, overlay.OverlayWidget)
HotkeyGroupOverlay.ATTRS{
    desc='Shows hotkey labels on a resolved native control group.',
    version='1',
    default_enabled=true,
    default_pos={x=1, y=1},
    fullscreen=false,
    full_interface=true,
    frame={l=0, t=0, w=1, h=1},
    overlay_onupdate_max_freq_seconds=0,
    model_builder=DEFAULT_NIL,
    label_anchor_kind=HotkeyLabelAnchor.BOTTOM_RIGHT,
    label_pen=COLOR_WHITE,
    label_inset_x=0,
    label_inset_y=0,
}

---Initializes the model and an inert initial snapshot.
function HotkeyGroupOverlay:init()
    assert(type(self.model_builder) == 'function',
        'HotkeyGroupOverlay.model_builder must be a function')
    self.model = self.model_builder()
    assert(type(self.model) == 'table' and type(self.model.build_snapshot) == 'function',
        'HotkeyGroupOverlay.model must support build_snapshot()')
    self.latest_snapshot = {
        active=false, layout_signature='init', bounds=nil, buttons={},
    }
    self.resolved_label_pen = self:resolve_label_pen()
    self.frame = {l=0, t=0, w=1, h=1}
end

---Builds a graphics pen that preserves the native tile beneath each label.
---@return any pen
function HotkeyGroupOverlay:resolve_label_pen()
    local screen = dfhack and dfhack.screen
    local font = df and df.global and df.global.init and
        df.global.init.font or nil
    local font_base = font and font.small_font_texpos and
        font.small_font_texpos[0] or nil
    if not screen or type(screen.inGraphicsMode) ~= 'function' or
            not screen.inGraphicsMode() or type(font_base) ~= 'number' or
            font_base <= 0 or not dfhack.pen or
            type(dfhack.pen.parse) ~= 'function' then
        return self.label_pen
    end
    return dfhack.pen.parse(self.label_pen, {
        tile=font_base,
        tile_color=true,
        keep_lower=true,
    })
end

---Refreshes the model snapshot used for frame and body layout.
function HotkeyGroupOverlay:sync_snapshot()
    self.latest_snapshot = self.model:build_snapshot()
end

---Fits the transparent host frame to the resolved screen-space group bounds.
---@param parent_rect gui.ViewRect|nil
---@return boolean changed
function HotkeyGroupOverlay:apply_snapshot_frame(parent_rect)
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
    self.frame.l, self.frame.t, self.frame.w, self.frame.h = l, t, w, h
    return changed
end

---Returns a clamped label anchor in overlay-local coordinates.
---@param bounds dwarfui.HotkeyRect
---@param label string
---@return integer x
---@return integer y
function HotkeyGroupOverlay:label_position(bounds, label)
    local right = bounds.x2 - #label + 1
    local bottom = bounds.y2
    local left_anchor = self.label_anchor_kind == HotkeyLabelAnchor.TOP_LEFT or
        self.label_anchor_kind == HotkeyLabelAnchor.BOTTOM_LEFT
    local top_anchor = self.label_anchor_kind == HotkeyLabelAnchor.TOP_LEFT or
        self.label_anchor_kind == HotkeyLabelAnchor.TOP_RIGHT
    local x = left_anchor and bounds.x1 or right
    local y = top_anchor and bounds.y1 or bottom
    x = x + ((x == bounds.x1) and self.label_inset_x or -self.label_inset_x)
    y = y + ((y == bounds.y1) and self.label_inset_y or -self.label_inset_y)
    return math.max(bounds.x1, math.min(bounds.x2, x)),
        math.max(bounds.y1, math.min(bounds.y2, y))
end

---Renders one resolved label using local coordinates relative to the group frame.
---@param dc gui.Painter
---@param button dwarfui.ResolvedHotkeyButton
---@param group_bounds dwarfui.HotkeyRect
function HotkeyGroupOverlay:render_button_label(dc, button, group_bounds)
    if not button or type(button.label) ~= 'string' or button.label == '' then return end
    local local_bounds = geometry.to_local(button.bounds,
        {x=group_bounds.x1, y=group_bounds.y1})
    if not local_bounds then return end
    local x, y = self:label_position(local_bounds, button.label)
    dc:seek(x, y):string(button.label, self.resolved_label_pen)
end

---Synchronizes the snapshot and renders through the resolved widget frame.
---@param dc gui.Painter
function HotkeyGroupOverlay:render(dc)
    self:sync_snapshot()
    if self:apply_snapshot_frame(self.frame_parent_rect) and self.frame_parent_rect then
        self:updateLayout(self.frame_parent_rect)
    end
    HotkeyGroupOverlay.super.render(self, dc)
end

---Paints all resolved labels through the frame-local body painter.
---@param dc gui.Painter
function HotkeyGroupOverlay:onRenderBody(dc)
    local bounds = self.latest_snapshot and self.latest_snapshot.bounds
    if not bounds then return end
    for _, button in ipairs(self.latest_snapshot.buttons or {}) do
        self:render_button_label(dc, button, bounds)
    end
end

---Tracks native movement and resizes the host frame without consuming input.
function HotkeyGroupOverlay:preUpdateLayout(parent_rect)
    self:sync_snapshot()
    self:apply_snapshot_frame(parent_rect)
end

---Refreshes geometry continuously so same-resolution movement is reflected.
function HotkeyGroupOverlay:overlay_onupdate()
    self:sync_snapshot()
    if self:apply_snapshot_frame(self.frame_parent_rect) and self.frame_parent_rect then
        self:updateLayout()
    end
end

---Passes all keyboard and pointer input through to the native interface.
---@param _keys table
---@return false
function HotkeyGroupOverlay:onInput(_keys)
    return false
end
