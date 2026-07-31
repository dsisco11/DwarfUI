local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

---Creates a painter double that records rendered label writes.
---@return table
local function painter()
    local dc = {strings={}}
    function dc:seek(x, y)
        self.x, self.y = x, y
        return self
    end
    function dc:string(text, pen)
        table.insert(self.strings, {x=self.x, y=self.y, text=text, pen=pen})
        return self
    end
    return dc
end

---Loads the hotkey overlay with isolated collaborators and model snapshots.
---@param state table
---@return table
local function load_overlay(state)
    local widgets = widget_harness.widgets()
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    local model = {
        build_snapshot=function()
            state.snapshot_reads = (state.snapshot_reads or 0) + 1
            return state.snapshot
        end,
    }

    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui-ui-hotkeys.lua', {
            globals={
                defclass=widget_harness.defclass,
                COLOR_WHITE='white',
            },
            require_modules={
                ['plugins.overlay']={OverlayWidget=OverlayWidget},
            },
            reqscript={
                ['dwarfui/ui_hotkeys']={
                    UiHotkeyModel=function() return model end,
                },
            },
        })

    return module.UiMenuHotkeysOverlay{
        model_builder=function() return model end,
    }
end

describe('DwarfUI UI hotkeys overlay', function()
    it('declares a default-enabled bounded dwarfmode overlay', function()
        local state = {snapshot={active=false, buttons={}}}
        local overlay = load_overlay(state)

        assert.is_true(overlay.default_enabled)
        assert.equals('dwarfmode/Default', overlay.viewscreens)
        assert.is_true(overlay.hotspot)
        assert.is_false(overlay.fullscreen)
        assert.is_true(overlay.full_interface)
        assert.equals(0, overlay.overlay_onupdate_max_freq_seconds)
        assert.is_false(overlay:onInput({_MOUSE_L=true}))
    end)

    it('renders live model labels and includes the citizen hotkey token',
            function()
        local state = {
            snapshot={
                active=true,
                layout_signature='80x25|test',
                buttons={{
                    semantic_id='citizens',
                    action_binding='D_UNITLIST',
                    bounds={x1=10, y1=20, x2=15, y2=22},
                    label='u',
                }},
                bounds={x1=10, y1=20, x2=15, y2=22},
            },
            snapshot_reads=0,
        }
        local overlay = load_overlay(state)
        overlay:updateLayout(widget_harness.rect(0, 0, 80, 25))

        local dc = painter()
        overlay:render(dc)

        assert.is_true(state.snapshot_reads >= 1)
        assert.equals(1, #dc.strings)
        assert.same({x=15, y=20, text='u', pen='white'}, dc.strings[1])
    end)

    it('resamples both on update and on render to track layout drift',
            function()
        local state = {
            snapshot={active=false, layout_signature='inactive', buttons={}},
            snapshot_reads=0,
        }
        local overlay = load_overlay(state)
        overlay:preUpdateLayout(widget_harness.rect(0, 0, 80, 25))

        overlay:overlay_onupdate()
        overlay:render(painter())

        assert.equals(3, state.snapshot_reads)
    end)
end)
