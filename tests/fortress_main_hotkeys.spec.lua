local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local dwarfuicore_root = require('support.dwarfuicore_root')
local widget_harness = require('support.widget_harness')

local function load_group()
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
    local environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/groups/fortress_main.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfui/hotkeys/geometry']=geometry_environment,
                ['dwarfui/hotkeys/layout_provider']=provider_environment,
                ['dwarfui/hotkeys/model']=model_environment,
            },
        })
    return environment.FortressMainGroup, model_environment.HotkeyGroupModel
end

describe('DwarfUI fortress main hotkey group', function()
    it('declares the canonical semantic order and DF actions', function()
        local group = load_group()
        assert.equals('fortress-main-toolbar', group.definition.group_id)
        assert.equals(8, #group.definition.buttons)
        assert.same({'citizens', 'tasks', 'places', 'labor', 'orders', 'nobles', 'objects', 'justice'},
            (function()
                local result = {}
                for _, button in ipairs(group.definition.buttons) do result[#result + 1] = button.semantic_id end
                return result
            end)())
        assert.same({'D_UNITLIST', 'D_JOBLIST', 'D_LOCATIONS', 'D_LABOR', 'D_ORDERS', 'D_NOBLES', 'D_ARTLIST', 'D_JUSTICE'},
            (function()
                local result = {}
                for _, button in ipairs(group.definition.buttons) do result[#result + 1] = button.action_binding end
                return result
            end)())
    end)

    it('uses the rendered native strip provider without input simulation', function()
        local group = load_group()
        local definition = group.definition
        local provider = definition.layout_provider
        local tiles = function(x, y)
            return x >= 10 and x <= 49 and y >= 26 and y <= 29 and
                {tile=1, write_to_lower=true} or {tile=0}
        end
        local layout, failure = provider({width=100, height=30, read_tile=tiles}, definition)
        assert.is_nil(failure)
        assert.equals(10, layout.bounds.x1)
        assert.equals(49, layout.bounds.x2)
        assert.equals(8, #definition.buttons)
    end)

    it('retains the default Citizens u label regression', function()
        local group, Model = load_group()
        local model = Model{
            definition=group.definition,
            active_provider=function() return true end,
            dimensions_provider=function() return 80, 25 end,
            binding_lookup=function(action)
                return action == 'D_UNITLIST' and 'u' or nil
            end,
            layout_provider=function()
                return {
                    group_id=group.definition.group_id,
                    bounds={x1=0, y1=20, x2=39, y2=23},
                    elements={citizens={bounds={x1=0, y1=20, x2=4, y2=23}}},
                    signature='citizens-u',
                }
            end,
        }
        local snapshot = model:build_snapshot()
        assert.equals(1, #snapshot.buttons)
        assert.equals('citizens', snapshot.buttons[1].semantic_id)
        assert.equals('D_UNITLIST', snapshot.buttons[1].action_binding)
        assert.equals('u', snapshot.buttons[1].label)
    end)
end)
