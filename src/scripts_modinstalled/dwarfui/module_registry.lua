--@ module=true

---@class dwarfui.ModuleSpec
---@field name string
---@field contract string
---@field contract_type string|nil

---Dependencies precede consumers so reload constructs one coherent generation.
---@type dwarfui.ModuleSpec[]
MODULES = {
    {name='dwarfui/text', contract='wrap_text'},
    {name='dwarfui/widget_extensions', contract='install_pointer_attributes'},
    {
        name='dwarfui/pointer',
        contract='PointerDispatcher',
        contract_type='table',
    },
    {
        name='dwarfui/popover',
        contract='Popover',
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
    {
        name='dwarfui/tooltip',
        contract='TooltipRenderer',
        contract_type='table',
    },
    {name='dwarfui/tooltip_registration', contract='register'},
}

local REGISTRY_SCRIPT = 'dwarfui/module_registry'

---Loads and validates every registered module in dependency order.
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
