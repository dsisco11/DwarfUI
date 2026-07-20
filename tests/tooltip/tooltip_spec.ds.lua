-- Live product contracts for the singleton tooltip service.

local tooltip = reqscript('dwarfui/tooltip')

---Returns the product diagnostics registered in tests/dwarfspec/config.lua.
---@return table
local function diagnostics()
    return ds.tooltip_state()
end

---Recreates the service in the current UI stack after setting a virtual pointer.
---@param target table
local function restart_service_for_target(target)
    tooltip.unregister(target)
    assert.is_true(tooltip.register(target))
    ds.wait_frames(2)
end

describe('live singleton tooltip service', function()
    local screen

    before_each(function()
        screen = ds.show_fixture(
            'tests/tooltip/fixtures/tooltip.fixture.lua')
    end)

    it('targets normal screens and presents dynamic text after real renders',
            function()
        local target = ds.get(screen, 'tooltip_target')
        local mouse_x, mouse_y = ds.move_pointer(target)

        restart_service_for_target(target)

        local state = diagnostics()
        assert.equals(target, state.target)
        assert.is_true(state.screen.renderer.visible)
        assert.equals(('Automation dynamic tooltip %d,%d'):format(
            mouse_x - target.frame_body.x1, mouse_y - target.frame_body.y1),
            state.screen.renderer.tooltip_text)
        assert.equals(state.screen.frame_parent_rect,
            state.screen.renderer.frame_parent_rect)
    end)

    it('blocks targets covered by a modal screen through real rendering',
            function()
        ds.dismiss(screen)
        screen = ds.show_fixture(
            'tests/tooltip/fixtures/tooltip.fixture.lua',
            {blocker_visible=true})
        local target = ds.get(screen, 'tooltip_target')
        ds.move_pointer(target)
        restart_service_for_target(target)
        assert.is_nil(diagnostics().target)
        assert.is_false(diagnostics().screen.renderer.visible)
    end)

    it('z-order recovery forwards input over a newly opened screen', function()
        local target = ds.get(screen, 'tooltip_target')
        ds.move_pointer(target)
        restart_service_for_target(target)
        local state = diagnostics()
        assert.equals(target, state.target)
        ds.input('CUSTOM_A', state.screen)
        assert.equals('CUSTOM_A', screen.last_key)
        assert.is_false(state.screen:isMouseOver())

        local cover = ds.show_fixture(
            'tests/tooltip/fixtures/cover.fixture.lua')
        ds.wait_frames(2)
        assert.is_true(state.screen:hasFocus())
        ds.dismiss(cover)
    end)
end)
