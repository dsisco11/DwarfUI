--@ module=true

---Describes one reload-managed DwarfUI feature module contract.
---@class dwarfui.ModuleSpec
---@field name string
---@field contract string
---@field contract_type string|nil

---Dependencies precede consumers so reload constructs one coherent generation.
---@type dwarfui.ModuleSpec[]
MODULES = {
    {
        name='dwarfui/services',
        contract='clear_namespaces',
    },
    {
        name='dwarfui/widgets/asset_button',
        contract='AssetButton',
        contract_type='table',
    },
    {
        name='dwarfui/widgets/hover_action_rail',
        contract='HoverActionRail',
        contract_type='table',
    },
    {name='dwarfui/popover', contract='Popover', contract_type='table'},
    {
        name='dwarfui/ui_hotkeys',
        contract='UiHotkeyModel',
        contract_type='table',
    },
    {
        name='dwarfui/hotkeys/geometry',
        contract='HotkeyGeometry',
        contract_type='table',
    },
    {
        name='dwarfui/hotkeys/layout_provider',
        contract='HotkeyLayoutProvider',
        contract_type='table',
    },
    {
        name='dwarfui/hotkeys/model',
        contract='HotkeyGroupModel',
        contract_type='table',
    },
    {
        name='dwarfui/hotkeys/groups/fortress_main',
        contract='FortressMainGroup',
        contract_type='table',
    },
    {
        name='dwarfui/hotkeys/overlay',
        contract='HotkeyGroupOverlay',
        contract_type='table',
    },
    {
        name='dwarfui/mood_popover',
        contract='MoodPopoverModel',
        contract_type='table',
    },
    {
        name='dwarfui/minecart_route',
        contract='MinecartRouteSelection',
        contract_type='table',
    },
    {name='dwarfui/unit_card_task', contract='is_haul_job'},
}

local REGISTRY_SCRIPT = 'dwarfui/module_registry'

---Loads and validates every registered DwarfUI feature module in dependency order.
---@param loader fun(name: string): table
---@return table<string, table>
function load_all(loader)
    local loaded = {}
    for _, spec in ipairs(MODULES) do
        local module = loader(spec.name)
        local expected_type = spec.contract_type or 'function'
        local suffix = expected_type == 'function' and '()' or ''
        assert(type(module[spec.contract]) == expected_type,
            ('DwarfUI module %s is missing %s%s'):format(
                spec.name, spec.contract, suffix))
        loaded[spec.name] = module
    end
    return loaded
end

---Returns registry and module script names in safe environment-clear order.
---@return string[]
function get_script_names()
    local names = {REGISTRY_SCRIPT}
    for index = #MODULES, 1, -1 do
        table.insert(names, MODULES[index].name)
    end
    return names
end
