local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, registry = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/module_registry.lua')

describe('DwarfUI module registry', function()
    it('loads registered contracts in dependency order', function()
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

        assert.equals(#registry.MODULES, #calls)
        assert.equals('dwarfui/class', calls[1])
        assert.equals('dwarfui/text', calls[2])
        assert.equals('dwarfui/utils/numbers', calls[3])
        assert.equals('dwarfui/utils/immutable_enum', calls[4])
        assert.equals('dwarfui/utils/function_chain', calls[5])
        assert.equals('dwarfui/context_menu/definition', calls[6])
        assert.equals('dwarfui/context_menu/target', calls[7])
        assert.equals('dwarfui/context_menu/root_discovery', calls[8])
        assert.equals('dwarfui/pointer', calls[9])
        assert.equals('dwarfui/widget_extensions', calls[10])
        assert.equals('dwarfui/widgets/asset_button', calls[11])
        assert.equals('dwarfui/widgets/hover_action_rail', calls[12])
        assert.equals('dwarfui/pointer_poller', calls[13])
        assert.equals('dwarfui/tooltip_root_resolver', calls[14])
        assert.equals('dwarfui/context_menu/map_target', calls[15])
        assert.equals('dwarfui/context_menu/registration', calls[16])
        assert.equals('dwarfui/context_menu/input_sample', calls[17])
        assert.equals('dwarfui/context_menu/target_detector', calls[18])
        assert.equals('dwarfui/context_menu/input_hook', calls[19])
        assert.equals('dwarfui/context_menu/service', calls[20])
        assert.equals('dwarfui/context_menu/renderer', calls[21])
        assert.equals('dwarfui/context_menu/screen', calls[22])
        assert.equals('dwarfui/context_menu/api', calls[23])
        assert.equals('dwarfui/tooltip_target', calls[24])
        assert.equals('dwarfui/tooltip_target_detector', calls[25])
        assert.equals('dwarfui/tooltip_map_target', calls[26])
        assert.equals('dwarfui/tooltip', calls[#calls - 1])
        assert.equals('dwarfui/tooltip_registration', calls[#calls])
        assert.equals('table',
            type(loaded['dwarfui/widgets/asset_button']))
        assert.equals('table',
            type(loaded['dwarfui/widgets/hover_action_rail']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/definition']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/target']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/root_discovery']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/input_sample']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/target_detector']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/input_hook']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/service']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/renderer']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/screen']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/api']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/map_target']))
        assert.equals('table',
            type(loaded['dwarfui/context_menu/registration'].manager))
        assert.equals('table', type(loaded['dwarfui/utils/numbers']))
        assert.equals('table',
            type(loaded['dwarfui/utils/immutable_enum']))
        assert.equals('table',
            type(loaded['dwarfui/utils/function_chain']))
        assert.equals('table', type(loaded['dwarfui/pointer_poller']))
        assert.equals('table',
            type(loaded['dwarfui/tooltip_root_resolver']))
        assert.equals('table', type(loaded['dwarfui/tooltip_target']))
        assert.equals('table',
            type(loaded['dwarfui/tooltip_target_detector']))
        assert.equals('table',
            type(loaded['dwarfui/tooltip_map_target']))
        assert.equals('table',
            type(loaded['dwarfui/tooltip_service'].service))
        assert.equals('table',
            type(loaded['dwarfui/tooltip_render_hook'].manager))
        assert.equals('table', type(loaded['dwarfui/tooltip']))
    end)

    it('rejects a module that does not implement its contract', function()
        local ok, err = pcall(registry.load_all, function()
            return {}
        end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):find(
            'DwarfUI module dwarfui/class is missing is_instance_of()',
            1, true))
    end)

    it('clears consumers before their dependencies', function()
        local names = registry.get_script_names()
        local expected = {
            'dwarfui/module_registry',
            'dwarfui/tooltip_registration',
            'dwarfui/tooltip',
            'dwarfui/unit_card_task',
            'dwarfui/minecart_route',
            'dwarfui/mood_popover',
            'dwarfui/popover',
            'dwarfui/tooltip_render_hook',
            'dwarfui/tooltip_service',
            'dwarfui/tooltip_map_target',
            'dwarfui/tooltip_target_detector',
            'dwarfui/tooltip_target',
            'dwarfui/context_menu/api',
            'dwarfui/context_menu/screen',
            'dwarfui/context_menu/renderer',
            'dwarfui/context_menu/service',
            'dwarfui/context_menu/input_hook',
            'dwarfui/context_menu/target_detector',
            'dwarfui/context_menu/input_sample',
            'dwarfui/context_menu/registration',
            'dwarfui/context_menu/map_target',
            'dwarfui/tooltip_root_resolver',
            'dwarfui/pointer_poller',
            'dwarfui/widgets/hover_action_rail',
            'dwarfui/widgets/asset_button',
            'dwarfui/widget_extensions',
            'dwarfui/pointer',
            'dwarfui/context_menu/root_discovery',
            'dwarfui/context_menu/target',
            'dwarfui/context_menu/definition',
            'dwarfui/utils/function_chain',
            'dwarfui/utils/immutable_enum',
            'dwarfui/utils/numbers',
            'dwarfui/text',
            'dwarfui/class',
        }

        assert.equals(#registry.MODULES + 1, #names)
        assert.same(expected, names)
    end)
end)
