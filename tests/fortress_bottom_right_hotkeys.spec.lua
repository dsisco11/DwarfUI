local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local dwarfuicore_root = require('support.dwarfuicore_root')
local widget_harness = require('support.widget_harness')

---Returns a deterministic interface texture identifier.
---@param _page string
---@param x integer
---@param y integer
---@return integer
local function find_graphics_tile(_page, x, y)
    return 1000 + y * 64 + x
end

---Loads the fortress bottom-right group with isolated collaborators.
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
        'src/scripts_modinstalled/dwarfui/hotkeys/groups/fortress_bottom_right.lua', {
            globals={dfhack={screen={
                findGraphicsTile=find_graphics_tile,
            }}},
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfui/hotkeys/geometry']=geometry_environment,
                ['dwarfui/hotkeys/layout_provider']=provider_environment,
                ['dwarfui/hotkeys/model']=model_environment,
            },
        })
    return environment.FortressBottomRightGroup
end

---Returns one tile from a Squads/World signature at an origin.
---@param origin_x integer
---@param origin_y integer
---@param x integer
---@param y integer
---@return table
local function signature_tile(origin_x, origin_y, x, y)
    local offset_x = x - origin_x
    local offset_y = y - origin_y
    if offset_x < 0 or offset_x > 7 or offset_y < 0 or offset_y > 2 then
        return {tile=0}
    end
    return {tile=find_graphics_tile(
        'INTERFACE_BITS', 24 + offset_x, 16 + offset_y)}
end

describe('DwarfUI fortress bottom-right hotkey group', function()
    it('declares the Squads and World DF actions', function()
        local group = load_group()
        assert.equals('fortress-bottom-right-toolbar',
            group.definition.group_id)
        assert.equals(2, #group.definition.buttons)
        assert.same({'squads', 'world'}, (function()
            local result = {}
            for _, button in ipairs(group.definition.buttons) do
                result[#result + 1] = button.semantic_id
            end
            return result
        end)())
        assert.same({'D_SQUADS', 'D_WORLD'}, (function()
            local result = {}
            for _, button in ipairs(group.definition.buttons) do
                result[#result + 1] = button.action_binding
            end
            return result
        end)())
    end)

    it('extracts only the native Squads and World buttons', function()
        local group = load_group()
        local definition = group.definition
        local layout, failure = definition.layout_provider({
            width=264,
            height=75,
            read_tile=function(x, y)
                return signature_tile(256, 72, x, y)
            end,
        }, definition)

        assert.is_nil(failure)
        assert.same({x1=256, y1=72, x2=263, y2=74}, layout.bounds)
        assert.same({x1=256, y1=72, x2=259, y2=74},
            layout.elements.squads.bounds)
        assert.same({x1=260, y1=72, x2=263, y2=74},
            layout.elements.world.bounds)
    end)

    it('rejects duplicate native sprite signatures as ambiguous', function()
        local group = load_group()
        local definition = group.definition
        local layout, failure = definition.layout_provider({
            width=400,
            height=75,
            read_tile=function(x, y)
                local first = signature_tile(310, 72, x, y)
                if first.tile ~= 0 then return first end
                return signature_tile(350, 72, x, y)
            end,
        }, definition)

        assert.is_nil(layout)
        assert.equals(4, failure.state)
        assert.equals('ambiguous', failure.reason)
    end)
end)
