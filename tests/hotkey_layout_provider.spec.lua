local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local dwarfuicore_root = require('support.dwarfuicore_root')

local function load_provider()
    local _, immutable_enum = module_loader.load(dwarfuicore_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local geometry_environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/geometry.lua', {
            reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
        })
    local environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/layout_provider.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfui/hotkeys/geometry']=geometry_environment.HotkeyGeometry,
            },
        })
    return environment.HotkeyLayoutProvider, geometry_environment.HotkeyGeometry
end

local function definition()
    return {group_id='fixture', buttons={
        {semantic_id='one', action_binding='A', element_id='one'},
        {semantic_id='two', action_binding='B', element_id='two'},
    }}
end

describe('DwarfUI hotkey layout providers', function()
    it('discovers and validates a rendered strip', function()
        local provider, geometry = load_provider()
        local read_tile = function(x, y)
            return (x >= 2 and x <= 5 and y >= 3 and y <= 4) and
                {tile=1, write_to_lower=true} or {tile=0}
        end
        local layout, err = provider.invoke(provider.rendered_strip({
            search_region={x1=0, y1=0, x2=8, y2=8}, expected_count=2,
            axis=geometry.HotkeyStripAxis.HORIZONTAL, element_ids={'one', 'two'},
            signature_data={source='fixture'},
        }), {read_tile=read_tile}, definition())
        assert.is_nil(err)
        assert.same({x1=2, y1=3, x2=3, y2=4}, layout.elements.one.bounds)
        assert.same({x1=4, y1=3, x2=5, y2=4}, layout.elements.two.bounds)
    end)

    it('maps ambiguity to a typed failure and contains provider errors', function()
        local provider, geometry = load_provider()
        local rendered = provider.rendered_strip({
            search_region={x1=0, y1=0, x2=10, y2=5}, expected_count=2,
            axis=geometry.HotkeyStripAxis.HORIZONTAL, element_ids={'one', 'two'},
        })
        local layout, err = provider.invoke(rendered, {
            read_tile=function(x, y)
                return ((x >= 1 and x <= 4) or (x >= 7 and x <= 10)) and y == 1 and
                    {tile=1} or {tile=0}
            end,
        }, definition())
        assert.is_nil(layout)
        assert.equals(provider.HotkeyGroupState.AMBIGUOUS, err.state)
        layout, err = provider.invoke(function() error('boom') end, {}, definition())
        assert.is_nil(layout)
        assert.equals(provider.HotkeyGroupState.UNAVAILABLE, err.state)
    end)

    it('uses widget traversal only for identified widget containers', function()
        local provider = load_provider()
        local calls = 0
        local native = provider.native_control({
            locate=function() return {kind='widget'} end,
            is_widget_container=function(value) return value.kind == 'widget' end,
            walk_widgets=function() calls = calls + 1; return {
                elements={one={bounds={x1=1,y1=1,x2=2,y2=2}}, two={bounds={x1=3,y1=1,x2=4,y2=2}}},
            } end,
        })
        local layout, err = provider.invoke(native, {}, definition())
        assert.is_nil(err)
        assert.equals(1, calls)
        assert.equals(1, layout.bounds.x1)

        local extracted = provider.native_control({
            locate=function() return {kind='native'} end,
            is_widget_container=function() return false end,
            extract=function() return {
                elements={one={x1=5,y1=5,x2=6,y2=6}, two={x1=7,y1=5,x2=8,y2=6}},
            } end,
        })
        layout, err = provider.invoke(extracted, {}, definition())
        assert.is_nil(err)
        assert.equals(5, layout.bounds.x1)
    end)
end)
