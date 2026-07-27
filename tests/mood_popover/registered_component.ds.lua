-- Deterministic registered-component coverage for the mood popover overlay.

describe('registered mood popover component with injected providers', function()
    it('renders injected component data through the registry-owned instance',
            function()
        -- Setup uses the real registry-owned instance while its data sources
        -- are replaced with deterministic component providers.
        local native_subject = ds.mountNativeScreen()
        local initially_hauling_open = ds.hasFocus('dwarfmode/Hauling')
        if initially_hauling_open then
            ds.input('LEAVESCREEN')
            ds.await('native Hauling menu closes for mood component coverage',
                function()
                    return ds.hasFocus('dwarfmode/Default')
                end)
        end
        local overlay = require('plugins.overlay')
        overlay.rescan()

        local name = 'dwarfui-mood-popover.mood_popover'
        local entry = assert(overlay.get_state().db[name],
            ('overlay is not registered: %s'):format(name))
        local widget = assert(entry.widget, 'registered overlay has no instance')
        assert.is_true(widget.fullscreen)
        assert.is_true(widget.hotspot)
        assert.equals(widget.frame_parent_rect.width, widget.frame_rect.width)
        assert.equals(widget.frame_parent_rect.height, widget.frame_rect.height)
        assert.equals(0, widget.frame_rect.x1)
        assert.equals(0, widget.frame_rect.y1)
        assert.is_true(widget.active_provider())

        local old_hover = widget.hover_provider
        local old_mouse = widget.mouse_provider
        local old_snapshot = widget.snapshot_provider
        local old_active = widget.active_provider
        local ok, failure = xpcall(function()
            widget.active_provider = function() return true end
            widget.hover_provider = function()
                return df.main_hover_instruction.INFO_STRESSED_0
            end
            widget.mouse_provider = function() return 10, 3 end
            widget.snapshot_provider = function()
                return {{id=1, name='Registered Citizen'}}
            end

            -- Interaction requests the normal registered-overlay render
            -- cadence without making a native moodlet-interaction claim.
            ds.redraw()

            -- Assertions prove only deterministic registered-component
            -- rendering and never claim native top-bar input coverage.
            assert.equals('Ecstatic', widget.selected_descriptor.label)
            assert.is_true(widget.popover.visible)
            assert.equals('Ecstatic (1)', widget.popover.header.text)
        end, debug.traceback)
        widget.hover_provider = old_hover
        widget.mouse_provider = old_mouse
        widget.snapshot_provider = old_snapshot
        widget.active_provider = old_active
        -- Direct clear is teardown for the injected registry-owned component.
        widget:clear()
        if initially_hauling_open then
            ds.input('D_HAULING')
            ds.await('original Hauling menu reopens after mood component coverage',
                function()
                    return ds.hasFocus('dwarfmode/Hauling')
                end)
        end
        ds.unmount()
        assert.is_true(ok, failure)
    end)
end)
