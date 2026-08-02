local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local dwarfuicore_root = require('support.dwarfuicore_root')
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

    ---Renders a test overlay body through a frame-local painter.
    ---@param dc table
    function OverlayWidget:render(dc)
        local overlay_widget = self
        local body_dc = {strings=dc.strings}

        ---Sets a frame-local cursor and records its screen-space position.
        ---@param x integer
        ---@param y integer
        ---@return table
        function body_dc:seek(x, y)
            self.x = x + overlay_widget.frame_body.x1
            self.y = y + overlay_widget.frame_body.y1
            return self
        end

        ---Records text written through the frame-local painter.
        ---@param value string
        ---@param pen any
        ---@return table
        function body_dc:string(value, pen)
            table.insert(self.strings, {
                x=self.x, y=self.y, text=value, pen=pen,
            })
            return self
        end

        self:onRenderBody(body_dc)
    end
    local _, immutable_enum = module_loader.load(dwarfuicore_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local geometry_environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/geometry.lua', {
            reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
        })
    local provider_environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/layout_provider.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfui/hotkeys/geometry']=geometry_environment,
            },
        })
    local model_environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/model.lua', {
            globals={defclass=widget_harness.defclass,
                DEFAULT_NIL=widget_harness.default_nil()},
            reqscript={
                ['dwarfui/hotkeys/geometry']=geometry_environment,
                ['dwarfui/hotkeys/layout_provider']=provider_environment,
            },
        })
    local overlay_environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/overlay.lua', {
            globals={defclass=widget_harness.defclass, COLOR_WHITE='white'},
            require_modules={['plugins.overlay']={OverlayWidget=OverlayWidget}},
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfui/hotkeys/geometry']=geometry_environment,
            },
        })
    local fortress_environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/groups/fortress_main.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfui/hotkeys/geometry']=geometry_environment,
                ['dwarfui/hotkeys/layout_provider']=provider_environment,
                ['dwarfui/hotkeys/model']=model_environment,
            },
        })
    local fortress_bottom_middle_environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/groups/fortress_bottom_middle.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfui/hotkeys/geometry']=geometry_environment,
                ['dwarfui/hotkeys/layout_provider']=provider_environment,
                ['dwarfui/hotkeys/model']=model_environment,
            },
        })
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
                ['dwarfui/hotkeys/overlay']=overlay_environment,
                ['dwarfui/hotkeys/groups/fortress_main']=fortress_environment,
                ['dwarfui/hotkeys/groups/fortress_bottom_middle']=
                    fortress_bottom_middle_environment,
            },
        })

    return module.UiMenuHotkeysOverlay{
        model_builder=function() return model end,
    }, module
end

describe('DwarfUI UI hotkeys overlay', function()
    it('declares a default-enabled bounded dwarfmode overlay', function()
        local state = {snapshot={active=false, buttons={}}}
        local overlay, module = load_overlay(state)

        assert.is_true(overlay.default_enabled)
        assert.equals('dwarfmode/Default', overlay.viewscreens)
        assert.is_true(overlay.hotspot)
        assert.is_false(overlay.fullscreen)
        assert.is_true(overlay.full_interface)
        assert.equals(0, overlay.overlay_onupdate_max_freq_seconds)
        assert.is_false(overlay:onInput({_MOUSE_L=true}))
        assert.equals(module.UiBottomMiddleHotkeysOverlay,
            module.OVERLAY_WIDGETS.bottom_middle_hotkeys)
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

    it('updates the host frame before rendering a newly resolved bottom group',
            function()
        local state = {
            snapshot={
                active=true,
                layout_signature='80x25|bottom-group',
                buttons={
                    {bounds={x1=10, y1=20, x2=15, y2=22}, label='u'},
                },
                bounds={x1=10, y1=20, x2=15, y2=22},
            },
        }
        local overlay = load_overlay(state)
        overlay:updateLayout(widget_harness.rect(0, 0, 80, 25))

        overlay:render(painter())

        assert.equals(10, overlay.frame_rect.x1)
        assert.equals(20, overlay.frame_rect.y1)
        assert.equals(6, overlay.frame_rect.width)
        assert.equals(3, overlay.frame_rect.height)
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
