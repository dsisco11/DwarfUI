local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local dwarfuicore_root = require('support.dwarfuicore_root')
local widget_harness = require('support.widget_harness')

---Loads the fortress bottom-middle group with isolated collaborators.
---@return table
local function load_group()
    local _, immutable_enum = module_loader.load(dwarfuicore_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local geometry_environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/geometry.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
            },
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
        'src/scripts_modinstalled/dwarfui/hotkeys/groups/fortress_bottom_middle.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfui/hotkeys/geometry']=geometry_environment,
                ['dwarfui/hotkeys/layout_provider']=provider_environment,
                ['dwarfui/hotkeys/model']=model_environment,
            },
        })
    return environment.FortressBottomMiddleGroup
end

describe('DwarfUI fortress bottom-middle hotkey group', function()
    it('declares the native button order and DF actions', function()
        local group = load_group()
        assert.equals('fortress-bottom-middle-toolbar',
            group.definition.group_id)
        assert.equals(12, #group.definition.buttons)
        assert.same({
            'dig', 'chop', 'gather', 'smooth', 'erase', 'building',
            'stockpiles', 'zones', 'burrows', 'hauling', 'traffic', 'items',
        }, (function()
            local result = {}
            for _, button in ipairs(group.definition.buttons) do
                result[#result + 1] = button.semantic_id
            end
            return result
        end)())
        assert.same({
            'D_DESIGNATE_DIG', 'D_DESIGNATE_CHOP', 'D_DESIGNATE_GATHER',
            'D_DESIGNATE_SMOOTH', 'D_DESIGNATE_ERASE', 'D_BUILDING',
            'D_STOCKPILES', 'D_CIVZONE', 'D_BURROWS', 'D_HAULING',
            'D_DESIGNATE_TRAFFIC', 'D_DESIGNATE_ITEMS',
        }, (function()
            local result = {}
            for _, button in ipairs(group.definition.buttons) do
                result[#result + 1] = button.action_binding
            end
            return result
        end)())
    end)

    it('extracts buttons around the native toolbar separators', function()
        local group = load_group()
        local definition = group.definition
        local layout, failure = definition.layout_provider({
            width=264,
            height=75,
            read_tile=function(x, y)
                return x >= 106 and x <= 158 and y >= 72 and y <= 74 and
                    {tile=1, write_to_lower=true} or {tile=0}
            end,
        }, definition)

        assert.is_nil(failure)
        assert.same({x1=107, y1=72, x2=157, y2=74}, layout.bounds)
        assert.same({x1=107, y1=72, x2=110, y2=74},
            layout.elements.dig.bounds)
        assert.same({x1=128, y1=72, x2=131, y2=74},
            layout.elements.building.bounds)
        assert.same({x1=154, y1=72, x2=157, y2=74},
            layout.elements.items.bounds)
    end)

    it('rejects multiple matching middle toolbars as ambiguous', function()
        local group = load_group()
        local definition = group.definition
        local layout, failure = definition.layout_provider({
            width=400,
            height=75,
            read_tile=function(x, y)
                local first = x >= 110 and x <= 162
                local second = x >= 220 and x <= 272
                return (first or second) and y >= 72 and y <= 74 and
                    {tile=1, write_to_lower=true} or {tile=0}
            end,
        }, definition)

        assert.is_nil(layout)
        assert.equals(4, failure.state)
        assert.equals('ambiguous', failure.reason)
    end)
end)
