local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, registry = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/module_registry.lua')

describe('DwarfUI feature module registry', function()
    it('loads DwarfUI-owned feature contracts in dependency order', function()
        local calls = {}
        local loaded = registry.load_all(function(name)
            table.insert(calls, name)
            for _, spec in ipairs(registry.MODULES) do
                if spec.name == name then
                    local value = spec.contract_type == 'table' and {} or
                        function() end
                    return {[spec.contract]=value}
                end
            end
        end)

        local expected = {
            'dwarfui/services',
            'dwarfui/widgets/asset_button',
            'dwarfui/widgets/hover_action_rail',
            'dwarfui/popover',
            'dwarfui/ui_hotkeys',
            'dwarfui/hotkeys/geometry',
            'dwarfui/hotkeys/layout_provider',
            'dwarfui/hotkeys/model',
            'dwarfui/hotkeys/groups/fortress_main',
            'dwarfui/hotkeys/groups/fortress_bottom_middle',
            'dwarfui/hotkeys/overlay',
            'dwarfui/mood_popover',
            'dwarfui/minecart_route',
            'dwarfui/unit_card_task',
        }
        assert.same(expected, calls)
        assert.equals(#expected, #registry.MODULES)
        assert.equals('table', type(loaded['dwarfui/minecart_route']))
        assert.equals('table', type(loaded['dwarfui/hotkeys/overlay']))
    end)

    it('does not register DwarfUICore implementation modules', function()
        for _, spec in ipairs(registry.MODULES) do
            assert.is_nil(spec.name:match('^dwarfuicore/'))
            assert.is_nil(spec.name:match('^dwarfui/(tooltip|context_menu)/'))
            assert.is_nil(spec.name:match('^dwarfui/(class|pointer|text|utils/)'))
        end
    end)

    it('rejects a feature module that does not implement its contract',
            function()
        local ok, err = pcall(registry.load_all, function()
            return {}
        end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):find(
            'DwarfUI module dwarfui/services is missing clear_namespaces',
            1, true))
    end)

    it('clears consumers before DwarfUI-owned dependencies', function()
        assert.same({
            'dwarfui/module_registry',
            'dwarfui/unit_card_task',
            'dwarfui/minecart_route',
            'dwarfui/mood_popover',
            'dwarfui/hotkeys/overlay',
            'dwarfui/hotkeys/groups/fortress_bottom_middle',
            'dwarfui/hotkeys/groups/fortress_main',
            'dwarfui/hotkeys/model',
            'dwarfui/hotkeys/layout_provider',
            'dwarfui/hotkeys/geometry',
            'dwarfui/ui_hotkeys',
            'dwarfui/popover',
            'dwarfui/widgets/hover_action_rail',
            'dwarfui/widgets/asset_button',
            'dwarfui/services',
        }, registry.get_script_names())
    end)
end)
