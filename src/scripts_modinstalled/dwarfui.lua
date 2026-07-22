--@ module=true

-- DwarfUI module validation and explicit development reload command.
--[====[
dwarfui
=======

Tags: fort | interface | development

Validates the installed DwarfUI runtime or explicitly reloads all DwarfUI
modules and overlays.

Usage
-----

    dwarfui
    dwarfui reload
]====]

local MODULE_REGISTRY_SCRIPT = 'dwarfui/module_registry'
local OVERLAY_SCRIPTS = {
    'dwarfui-mood-popover',
    'dwarfui-unit-card-task-details',
}

---Returns whether a value implements the DwarfUI registry contract.
---@param registry any
---@return boolean
local function is_valid_registry(registry)
    return type(registry) == 'table' and
        type(registry.load_all) == 'function' and
        type(registry.get_script_names) == 'function' and
        type(registry.MODULES) == 'table'
end

---Loads the registry and repairs a partially cleared script environment.
---@return table
local function load_module_registry()
    local registry = reqscript(MODULE_REGISTRY_SCRIPT)
    if not is_valid_registry(registry) then
        dfhack.run_command('devel/clear-script-env', MODULE_REGISTRY_SCRIPT)
        dfhack.run_script(MODULE_REGISTRY_SCRIPT)
        registry = reqscript(MODULE_REGISTRY_SCRIPT)
    end
    assert(is_valid_registry(registry),
        'DwarfUI could not load its module registry.')
    return registry
end

---Clears cached environments for script names that are currently loaded.
---@param script_names string[]
local function clear_script_environments(script_names)
    local loaded_names = {}
    for _, name in ipairs(script_names) do
        local path = dfhack.findScript(name)
        if path and dfhack.internal.scripts[path] then
            table.insert(loaded_names, name)
        end
    end
    if #loaded_names > 0 then
        dfhack.run_command('devel/clear-script-env', table.unpack(loaded_names))
    end
end

---Evicts overlay registrations so DFHack discovers their fresh classes.
local function reload_overlays()
    for _, script in ipairs(OVERLAY_SCRIPTS) do
        local path = assert(dfhack.findScript(script),
            'DwarfUI overlay script could not be found: ' .. script)
        dfhack.internal.scripts[path] = nil
    end
    require('plugins.overlay').rescan()
end

---Validates and returns the currently loaded DwarfUI module generation.
---@return table<string, table>
function initialize()
    return load_module_registry().load_all(reqscript)
end

---Rebuilds every DwarfUI module and overlay as one runtime generation.
---@return table<string, table>
function reload()
    local old_registry = load_module_registry()
    local old_script_names = old_registry.get_script_names()
    local old_modules = {}
    for _, name in ipairs(old_script_names) do
        if name ~= MODULE_REGISTRY_SCRIPT then
            table.insert(old_modules, name)
        end
    end
    clear_script_environments(old_modules)

    dfhack.run_command('devel/clear-script-env', MODULE_REGISTRY_SCRIPT)
    dfhack.run_script(MODULE_REGISTRY_SCRIPT)
    local fresh_registry = load_module_registry()

    local fresh_modules = {}
    for _, spec in ipairs(fresh_registry.MODULES) do
        table.insert(fresh_modules, spec.name)
    end
    clear_script_environments(fresh_modules)
    for _, spec in ipairs(fresh_registry.MODULES) do
        dfhack.run_script(spec.name)
    end

    reload_overlays()
    return fresh_registry.load_all(reqscript)
end

---Runs the DwarfUI validation or reload command.
---@param ... string
function main(...)
    local args = {...}
    if #args == 0 then
        initialize()
    elseif #args == 1 and args[1] == 'reload' then
        reload()
    else
        qerror('Usage: dwarfui [reload]')
    end
end

if not dfhack_flags.module then main(...) end
