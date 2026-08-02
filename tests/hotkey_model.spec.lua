local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local dwarfuicore_root = require('support.dwarfuicore_root')
local widget_harness = require('support.widget_harness')

local function load_model()
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
                ['dwarfui/hotkeys/geometry']=geometry_environment.HotkeyGeometry,
            },
        })
    local environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/model.lua', {
            globals={defclass=widget_harness.defclass, DEFAULT_NIL=widget_harness.default_nil()},
            reqscript={
                ['dwarfui/hotkeys/geometry']=geometry_environment.HotkeyGeometry,
                ['dwarfui/hotkeys/layout_provider']=provider_environment,
            },
        })
    return environment.HotkeyGroupModel, provider_environment.HotkeyLayoutProvider
end

local function definition()
    return {group_id='model-fixture', buttons={
        {semantic_id='one', action_binding='ACTION_ONE', element_id='one'},
        {semantic_id='two', action_binding='ACTION_TWO', element_id='two'},
    }}
end

describe('DwarfUI reusable hotkey model', function()
    it('uses the layout provider owned by the group definition by default', function()
        local Model, provider = load_model()
        local fixture_definition = definition()
        fixture_definition.layout_provider = function()
            return {group_id='model-fixture', bounds={x1=1,y1=1,x2=4,y2=2},
                elements={one={bounds={x1=1,y1=1,x2=2,y2=2}},
                    two={bounds={x1=3,y1=1,x2=4,y2=2}}},
                signature='definition-provider'}
        end
        local model = Model{
            definition=fixture_definition,
            active_provider=function() return true end,
            dimensions_provider=function() return 80, 25 end,
            binding_lookup=function() return 'u' end,
        }

        local snapshot = model:build_snapshot()

        assert.equals(provider.HotkeyGroupState.READY, snapshot.state)
        assert.equals('definition-provider', snapshot.layout_signature)
        assert.equals(2, #snapshot.buttons)
    end)

    it('accepts the DFHack module environment shape for its layout provider', function()
        local Model, provider = load_model()
        local model = Model{
            definition=definition(), active_provider=function() return true end,
            dimensions_provider=function() return 80, 25 end,
            binding_lookup=function() return 'u' end,
            layout_provider=function()
                return {group_id='model-fixture', bounds={x1=1,y1=1,x2=4,y2=2},
                    elements={one={bounds={x1=1,y1=1,x2=2,y2=2}}, two={bounds={x1=3,y1=1,x2=4,y2=2}}},
                    signature='module-environment'}
            end,
        }
        assert.equals(provider.HotkeyGroupState.READY, model:build_snapshot().state)
    end)

    it('maps semantic buttons and normalizes labels independently of geometry', function()
        local Model, provider = load_model()
        local signature = 'A'
        local labels = {ACTION_ONE='Shift-U', ACTION_TWO='Alt+F1'}
        local model = Model{
            definition=definition(),
            active_provider=function() return true end,
            dimensions_provider=function() return 80, 25 end,
            binding_lookup=function(action) return labels[action] end,
            layout_provider=function()
                return {group_id='model-fixture', bounds={x1=4,y1=5,x2=9,y2=7},
                    elements={
                        one={bounds={x1=4,y1=5,x2=6,y2=7}},
                        two={bounds={x1=7,y1=5,x2=9,y2=7}},
                    }, signature=signature}
            end,
        }
        local snapshot = model:build_snapshot()
        assert.equals(provider.HotkeyGroupState.READY, snapshot.state)
        assert.equals(2, #snapshot.buttons)
        assert.equals('u', snapshot.buttons[1].label)
        assert.equals('F1', snapshot.buttons[2].label)
        assert.equals('one', snapshot.buttons[1].element_id)
    end)

    it('re-resolves changed bindings without rebuilding cached geometry', function()
        local Model = load_model()
        local calls, labels = 0, {ACTION_ONE='u', ACTION_TWO=nil}
        local model = Model{
            definition=definition(), active_provider=function() return true end,
            dimensions_provider=function() return 80, 25 end,
            binding_lookup=function(action) return labels[action] end,
            layout_provider=function()
                calls = calls + 1
                return {group_id='model-fixture', bounds={x1=1,y1=1,x2=4,y2=2},
                    elements={one={bounds={x1=1,y1=1,x2=2,y2=2}}, two={bounds={x1=3,y1=1,x2=4,y2=2}}},
                    signature='stable'}
            end,
        }
        assert.equals(1, #model:build_snapshot().buttons)
        labels.ACTION_TWO = 'p'
        assert.equals(2, #model:build_snapshot().buttons)
        assert.equals(2, calls)
        assert.equals('stable', model.cached_signature)
    end)

    it('invalidates cached geometry after same-resolution movement', function()
        local Model = load_model()
        local origin = 1
        local model = Model{
            definition=definition(), active_provider=function() return true end,
            dimensions_provider=function() return 80, 25 end,
            binding_lookup=function() return 'u' end,
            layout_provider=function()
                return {group_id='model-fixture',
                    bounds={x1=origin,y1=1,x2=origin + 3,y2=2},
                    elements={
                        one={bounds={x1=origin,y1=1,x2=origin + 1,y2=2}},
                        two={bounds={x1=origin + 2,y1=1,x2=origin + 3,y2=2}},
                    },
                    signature='position:' .. origin}
            end,
        }
        local first = model:build_snapshot()
        local first_layout = model.cached_layout
        origin = 9
        local moved = model:build_snapshot()
        assert.equals(1, first.bounds.x1)
        assert.equals(9, moved.bounds.x1)
        assert.not_equals(first_layout, model.cached_layout)
        assert.equals('position:9', model.cached_signature)
    end)

    it('suppresses only buttons with missing geometry or bindings', function()
        local Model = load_model()
        local labels = {ACTION_ONE='u', ACTION_TWO=nil}
        local model = Model{
            definition=definition(), active_provider=function() return true end,
            dimensions_provider=function() return 80, 25 end,
            binding_lookup=function(action) return labels[action] end,
            layout_provider=function()
                return {group_id='model-fixture', bounds={x1=1,y1=1,x2=4,y2=2},
                    elements={one={bounds={x1=1,y1=1,x2=2,y2=2}}},
                    signature='partial'}
            end,
        }
        local missing_binding = model:build_snapshot()
        assert.equals(1, #missing_binding.buttons)
        assert.equals('one', missing_binding.buttons[1].semantic_id)

        labels.ACTION_ONE = nil
        labels.ACTION_TWO = 'p'
        local missing_geometry = model:build_snapshot()
        assert.equals(0, #missing_geometry.buttons)
        assert.equals(1, missing_geometry.bounds.x1)
    end)

    it('clears geometry on inactive or unavailable groups', function()
        local Model, provider = load_model()
        local active, available = true, true
        local model = Model{
            definition=definition(), active_provider=function() return active end,
            dimensions_provider=function() return 80, 25 end,
            binding_lookup=function() return 'u' end,
            layout_provider=function()
                if not available then
                    local _, failure = provider.failure(provider.HotkeyGroupState.AMBIGUOUS, 'test')
                    return nil, failure
                end
                return {group_id='model-fixture', bounds={x1=1,y1=1,x2=4,y2=2},
                    elements={one={bounds={x1=1,y1=1,x2=2,y2=2}}, two={bounds={x1=3,y1=1,x2=4,y2=2}}},
                    signature='stable'}
            end,
        }
        assert.equals(2, #model:build_snapshot().buttons)
        available = false
        local unavailable = model:build_snapshot()
        assert.equals(provider.HotkeyGroupState.AMBIGUOUS, unavailable.state)
        assert.is_nil(model.cached_layout)
        active = false
        assert.equals(provider.HotkeyGroupState.INACTIVE, model:build_snapshot().state)
    end)
end)
