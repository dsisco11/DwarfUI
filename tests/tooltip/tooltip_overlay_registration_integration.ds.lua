-- Real overlay-discovery integration contracts for the singleton tooltip.

local tooltip = reqscript('dwarfui/tooltip')
local overlay = require('plugins.overlay')

---Returns the product diagnostics registered in tests/dwarfspec/config.lua.
---@return table
local function diagnostics()
    return ds.tooltip_state()
end

describe('live singleton tooltip overlay registration', function()
    local native_subject
    local borrowed_screen
    local overlay_name
    local target_subject
    local widget
    local target
    local original_viewscreens

    before_each(function()
        borrowed_screen = assert(dfhack.gui.getDFViewscreen(true),
            'native fortress viewscreen is unavailable')
        native_subject = ds.mountNativeScreen()
        assert.is_true(ds.hasFocus('dwarfmode/Default'))
        local native_state = native_subject:inspect()
        assert.is_true(native_state.visible)
        assert.is_true(native_state.active)
        assert.equals('dwarfmode/Default',
            native_subject:getFocusList()[1])

        local staged = ds.stage_overlay_registration(
            'tests/tooltip/support/tooltip_overlay_registration.lua',
            'tooltip_probe')
        assert.equals(1, #staged.registered_names)
        overlay_name = staged.registered_names[1]
        ds.redraw()

        target_subject = ds.get('tooltip_target', {
            source='overlay',
            overlay=overlay_name,
        })
        target = target_subject:raw()
        widget = assert(target.parent_view,
            'staged tooltip target has no registered overlay parent')
        original_viewscreens = widget.viewscreens
    end)

    after_each(function()
        if widget then widget.viewscreens = original_viewscreens end
        if target then
            assert.is_true(tooltip.unregister(target))
        end
        if native_subject then
            ds.redraw()
            assert.is_not_equal(target, diagnostics().target)
        end
    end)

    it('honors real discovery, enablement, and focus eligibility', function()
        assert.is_true(overlay.isOverlayEnabled(overlay_name))
        local target_state = target_subject:inspect()
        assert.is_true(target_state.visible)
        assert.is_true(target_state.active)
        assert.equals('Automation overlay tooltip outside its narrow root.',
            target_state.tooltip)
        local body = assert(target_state.body,
            'registered tooltip target has no rendered bounds')
        local target_x = math.floor((body.x1 + body.x2) / 2)
        local target_y = math.floor((body.y1 + body.y2) / 2)

        -- Exact native-screen pointer placement and a completed redraw prove
        -- selection through the staged registry-owned overlay.
        ds.move_pointer(target_x, target_y)
        ds.redraw()
        ds.await('registered overlay tooltip target selected', function()
            local state = diagnostics()
            return state.target == target and state.screen.renderer.visible
        end)

        local state = diagnostics()
        assert.is_true(state.screen.renderer.frame.l +
            state.screen.renderer.frame.w - 1 >
            widget.frame_body.clip_x2)

        -- The staged overlay becomes ineligible solely through its viewscreen
        -- contract while its borrowed backing screen remains unchanged.
        widget.viewscreens = 'title'
        ds.redraw()
        assert.is_equal(borrowed_screen, dfhack.gui.getDFViewscreen(true))
        assert.is_equal(borrowed_screen.widgets, native_subject:raw())
        local ineligible_state = target_subject:inspect()
        assert.equals(target_state.tooltip, ineligible_state.tooltip)
        assert.is_nil(diagnostics().target)
        assert.is_false(state.screen.renderer.visible)

        widget.viewscreens = original_viewscreens
        ds.redraw()
        ds.move_pointer(target_x, target_y)
        ds.redraw()
        ds.await('focus-eligible tooltip target selected again', function()
            local selected = diagnostics()
            return selected.target == target and
                selected.screen.renderer.visible
        end)

        assert.is_true(overlay.overlay_command(
            {'disable', overlay_name}, true))
        ds.redraw()
        assert.is_false(overlay.isOverlayEnabled(overlay_name))
        assert.is_nil(diagnostics().target)
        assert.is_false(state.screen.renderer.visible)
        assert.is_equal(borrowed_screen, dfhack.gui.getDFViewscreen(true),
            'native attachment dismissed or replaced the game screen')
    end)
end)
