-- Real overlay-discovery integration contracts for the singleton tooltip.

local gui = require('gui')
local widgets = require('gui.widgets')
local tooltip = reqscript('dwarfui/tooltip')
local overlay = require('plugins.overlay')

---@class tests.TooltipRegistrationScreen: gui.ZScreen
local TooltipRegistrationScreen = defclass(nil, gui.ZScreen)
TooltipRegistrationScreen.ATTRS{initial_pause=false}

---Builds a pointer target aligned with the registered probe overlay.
function TooltipRegistrationScreen:init()
    self:addviews{
        widgets.Panel{
            view_id='pointer_target',
            frame={l=1, t=1, w=8, h=4},
        },
    }
end

---Returns the product diagnostics registered in tests/dwarfspec/config.lua.
---@return table
local function diagnostics()
    return ds.tooltip_state()
end

---Returns the overlay registered by the active DwarfSpec run.
---@return string|nil, table|nil
local function find_staged_overlay()
    for name, entry in pairs(overlay.get_state().db) do
        if name:find('dwarfspec_', 1, true) and
                name:find('tooltip_probe', 1, true) then
            return name, entry
        end
    end
    return nil, nil
end

---Returns whether an overlay accepts the live underlying DF viewscreen.
---@param widget table
---@return boolean
local function matches_live_viewscreen(widget)
    local current = dfhack.gui.getDFViewscreen(true)
    if not current then return false end
    for _, focus in ipairs(overlay.normalize_list(widget.viewscreens)) do
        if focus == 'all' or dfhack.gui.matchFocusString(
                overlay.simplify_viewscreen_name(focus), current) then
            return true
        end
    end
    return false
end

describe('live singleton tooltip overlay registration', function()
    local overlay_name
    local widget
    local target
    local original_viewscreens

    before_each(function()
        ds.mount(TooltipRegistrationScreen, {initial_pause=false})
        ds.stage_overlay_registration(
            'tests/tooltip/support/tooltip_overlay_registration.lua',
            'tooltip_probe')
        local overlay_entry
        overlay_name, overlay_entry = find_staged_overlay()
        assert.is_truthy(overlay_entry)
        widget = overlay_entry.widget
        target = widget.tooltip_target
        original_viewscreens = widget.viewscreens
    end)

    after_each(function()
        widget.viewscreens = original_viewscreens
        tooltip.unregister(target)
        ds.wait_frames(2)
    end)

    it('honors real discovery, enablement, and focus eligibility', function()
        assert.is_true(overlay.isOverlayEnabled(overlay_name))
        assert.equals(widget, overlay.get_state().db[overlay_name].widget)
        assert.is_true(matches_live_viewscreen(widget))
        ds.await('registered overlay layout', function()
            return target.frame_body and target.frame_body.height > 0
        end)
        local pointer_target = ds.get('pointer_target')
        pointer_target:move_pointer('top_left')
        tooltip.unregister(target)
        assert.is_true(tooltip.register(target))
        ds.await('registered overlay tooltip target selected', function()
            local state = diagnostics()
            return state.target == target and state.screen.renderer.visible
        end)

        local state = diagnostics()
        assert.is_true(state.screen.renderer.frame.l +
            state.screen.renderer.frame.w - 1 >
            widget.frame_body.clip_x2)

        widget.viewscreens = 'title'
        pointer_target:move_pointer('top_left')
        assert.is_nil(diagnostics().target)
        assert.is_false(state.screen.renderer.visible)

        widget.viewscreens = original_viewscreens
        assert.is_true(overlay.overlay_command(
            {'disable', overlay_name}, true))
        pointer_target:move_pointer('top_left')
        assert.is_nil(diagnostics().target)
        assert.is_false(state.screen.renderer.visible)
    end)
end)
