--@ module=true

-- Compatibility registration wrapper for the fortress main hotkey group.

local generic_overlay = reqscript('dwarfui/hotkeys/overlay')
local fortress_main = reqscript('dwarfui/hotkeys/groups/fortress_main')
local fortress_bottom_middle =
    reqscript('dwarfui/hotkeys/groups/fortress_bottom_middle')

---@class dwarfui.UiMenuHotkeysOverlay: dwarfui.HotkeyGroupOverlay
---@field model_builder fun(): dwarfui.HotkeyGroupModel
UiMenuHotkeysOverlay = defclass(UiMenuHotkeysOverlay,
    generic_overlay.HotkeyGroupOverlay)
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
    label_anchor_kind=generic_overlay.HotkeyLabelAnchor.BOTTOM_RIGHT,
    label_pen=COLOR_WHITE,
    label_inset_x=0,
    label_inset_y=0,
    model_builder=function()
        return fortress_main.FortressMainGroup.create_model()
    end,
}

---Constructs the compatibility overlay using the reusable fortress group.
function UiMenuHotkeysOverlay:init()
    UiMenuHotkeysOverlay.super.init(self)
end

---@class dwarfui.UiBottomMiddleHotkeysOverlay: dwarfui.HotkeyGroupOverlay
---@field model_builder fun(): dwarfui.HotkeyGroupModel
UiBottomMiddleHotkeysOverlay = defclass(UiBottomMiddleHotkeysOverlay,
    generic_overlay.HotkeyGroupOverlay)
UiBottomMiddleHotkeysOverlay.ATTRS{
    desc='Shows hotkey labels on the fortress bottom-middle buttons.',
    version='1',
    default_enabled=true,
    default_pos={x=1, y=1},
    viewscreens='dwarfmode/Default',
    hotspot=true,
    fullscreen=false,
    full_interface=true,
    frame={l=0, t=0, w=1, h=1},
    overlay_onupdate_max_freq_seconds=0,
    label_anchor_kind=generic_overlay.HotkeyLabelAnchor.BOTTOM_RIGHT,
    label_pen=COLOR_WHITE,
    label_inset_x=0,
    label_inset_y=0,
    model_builder=function()
        return fortress_bottom_middle.FortressBottomMiddleGroup.create_model()
    end,
}

---Constructs the bottom-middle overlay using its reusable fortress group.
function UiBottomMiddleHotkeysOverlay:init()
    UiBottomMiddleHotkeysOverlay.super.init(self)
end

OVERLAY_WIDGETS = {
    ui_hotkeys=UiMenuHotkeysOverlay,
    bottom_middle_hotkeys=UiBottomMiddleHotkeysOverlay,
}
