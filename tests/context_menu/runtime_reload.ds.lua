-- Live DwarfUI reload-generation and process-owner acceptance.

describe('live context-menu runtime reload', function()
    it('reconstructs one clean authoritative generation', function()
        dfhack.run_command('dwarfui', 'reload')
        ds.wait_frames(2)

        local service =
            reqscript('dwarfui/context_menu/service').service
        local registrations =
            reqscript('dwarfui/context_menu/registration').manager
        local diagnostics = service:get_diagnostics()
        assert.is_true(diagnostics.started)
        assert.is_false(diagnostics.disabled)
        assert.is_false(diagnostics.open)
        assert.equals(0,
            diagnostics.registrations.widget_registration_count)
        assert.equals(0,
            diagnostics.registrations.map_registration_count)
        assert.is_true(registrations:_module_is_current())
        assert.is_function(
            dfhack.onStateChange.dwarfui_context_menu)
    end)
end)
