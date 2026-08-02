local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local dwarfuicore_root = require('support.dwarfuicore_root')
local widget_harness = require('support.widget_harness')

local function painter()
    local dc = {strings={}}
    function dc:seek(x, y) self.x, self.y = x, y; return self end
    function dc:string(text, pen)
        self.strings[#self.strings + 1] = {x=self.x, y=self.y, text=text, pen=pen}
        return self
    end
    return dc
end

local function load_overlay()
    local _, immutable_enum = module_loader.load(dwarfuicore_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local geometry_environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/geometry.lua', {
            reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
        })
    local widgets = widget_harness.widgets()
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    local environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/overlay.lua', {
            globals={defclass=widget_harness.defclass, COLOR_WHITE='white'},
            require_modules={['plugins.overlay']={OverlayWidget=OverlayWidget}},
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfui/hotkeys/geometry']=geometry_environment.HotkeyGeometry,
            },
        })
    return environment.HotkeyGroupOverlay, environment.HotkeyLabelAnchor
end

local function snapshot(group_id, x, y, labels)
    return {
        group_id=group_id, active=true, layout_signature=group_id .. x,
        bounds={x1=x, y1=y, x2=x + 7, y2=y + 3},
        buttons={
            {element_id='one', bounds={x1=x, y1=y, x2=x + 3, y2=y + 3}, label=labels[1]},
            {element_id='two', bounds={x1=x + 4, y1=y, x2=x + 7, y2=y + 3}, label=labels[2]},
        },
    }
end

describe('DwarfUI bounded hotkey overlay', function()
    it('fits to group bounds and paints screen geometry in local coordinates', function()
        local Overlay, anchor = load_overlay()
        local state = {snapshot=snapshot('one', 10, 20, {'u', 'p'})}
        local instance = Overlay{
            model_builder=function() return {build_snapshot=function() return state.snapshot end} end,
            label_anchor_kind=anchor.TOP_RIGHT,
        }
        instance:preUpdateLayout(widget_harness.rect(0, 0, 80, 25))
        assert.same({l=10, t=20, w=8, h=4}, instance.frame)
        local dc = painter()
        instance:onRenderBody(dc)
        assert.same({x=3, y=0, text='u', pen='white'}, dc.strings[1])
        assert.same({x=7, y=0, text='p', pen='white'}, dc.strings[2])
        assert.is_false(instance:onInput({_MOUSE_L=true}))
    end)

    it('tracks movement and collapses unavailable groups independently', function()
        local Overlay = load_overlay()
        local first = {snapshot=snapshot('first', 2, 3, {'a', 'b'})}
        local second = {snapshot=snapshot('second', 30, 10, {'c', 'd'})}
        local function make(state)
            return Overlay{model_builder=function()
                return {build_snapshot=function() return state.snapshot end}
            end}
        end
        local left, right = make(first), make(second)
        local parent = widget_harness.rect(0, 0, 80, 25)
        left:preUpdateLayout(parent); right:preUpdateLayout(parent)
        first.snapshot = snapshot('first', 5, 6, {'a', 'b'})
        left:overlay_onupdate()
        assert.equals(5, left.frame.l)
        assert.equals(30, right.frame.l)
        second.snapshot = {active=true, bounds=nil, buttons={}}
        right:overlay_onupdate()
        assert.same({l=0, t=0, w=1, h=1}, right.frame)
        assert.equals(5, left.frame.l)
    end)
end)
