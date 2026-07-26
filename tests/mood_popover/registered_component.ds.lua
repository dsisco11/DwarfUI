-- Deterministic registered-component coverage for the mood popover overlay.

describe('registered mood popover component with injected providers', function()
    it('renders injected component data through the registry-owned instance',
            function()
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

            -- The normal registered-overlay render cadence samples the
            -- injected providers and renders their deterministic component
            -- state without making a native moodlet-interaction claim.
            ds.wait_frames(2)
            assert.equals('Ecstatic', widget.selected_descriptor.label)
            assert.is_true(widget.popover.visible)
            assert.equals('Ecstatic (1)', widget.popover.header.text)
        end, debug.traceback)
        widget.hover_provider = old_hover
        widget.mouse_provider = old_mouse
        widget.snapshot_provider = old_snapshot
        widget.active_provider = old_active
        widget:clear()
        assert.is_true(ok, failure)
    end)
end)
