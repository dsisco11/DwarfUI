--@ module=true

-- DwarfUI validation and explicit development reload command.
--[====[
dwarfui
=======

Tags: fort | interface | development

Validates the installed DwarfUI feature runtime or explicitly reloads
DwarfUI-owned modules and overlays. DwarfUICore has its own reload command.

Usage
-----

    dwarfui
    dwarfui reload
]====]

local MODULE_REGISTRY_SCRIPT = 'dwarfui/module_registry'
local SERVICES_SCRIPT = 'dwarfui/services'
local OVERLAY_SCRIPTS = {
    'dwarfui-ui-hotkeys',
    'dwarfui-mood-popover',
    'dwarfui-minecart-route-markers',
    'dwarfui-unit-card-task-details',
}

---Clears feature-local state for every current DwarfUI overlay before DFHack
---discards its registry.
local function clear_overlay_local_state()
    local db = require('plugins.overlay').get_state().db
    for _, script in ipairs(OVERLAY_SCRIPTS) do
        local prefix = script .. '.'
        for name, entry in pairs(db) do
            if name:sub(1, #prefix) == prefix then
                local clear_local = entry.widget.dwarfui_clear_local_state or
                    entry.widget.overlay_ondisable
                if clear_local then
                    clear_local()
                end
            end
        end
    end
end

---Loads the DwarfUI-owned module registry.
---@return table registry
local function load_module_registry()
    return reqscript(MODULE_REGISTRY_SCRIPT)
end

---Clears cached environments only for loaded DwarfUI-owned scripts.
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

---Evicts DwarfUI overlay registrations so DFHack discovers their fresh classes.
local function reload_overlays()
    for _, script in ipairs(OVERLAY_SCRIPTS) do
        local path = assert(dfhack.findScript(script),
            'DwarfUI overlay script could not be found: ' .. script)
        dfhack.internal.scripts[path] = nil
    end
    require('plugins.overlay').rescan()
end

---Validates and returns the currently loaded DwarfUI feature generation.
---@return table<string, table>
function initialize()
    return load_module_registry().load_all(reqscript)
end

---Clears local overlay state, then clears both DwarfUI-owned service namespaces.
---@return boolean changed
function teardown()
    clear_overlay_local_state()
    local services = reqscript(SERVICES_SCRIPT)
    services.refresh()
    return services.clear_namespaces()
end

---Rebuilds DwarfUI-owned modules and overlays without reloading DwarfUICore.
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
    teardown()
    clear_script_environments(old_modules)

    dfhack.run_command('devel/clear-script-env', MODULE_REGISTRY_SCRIPT)
    dfhack.run_script(MODULE_REGISTRY_SCRIPT)
    local fresh_registry = load_module_registry()

    local fresh_modules = {}
    for _, spec in ipairs(fresh_registry.MODULES) do
        table.insert(fresh_modules, spec.name)
    end
    clear_script_environments(fresh_modules)
    for _, script_name in ipairs(fresh_modules) do
        dfhack.run_script(script_name)
    end

    reload_overlays()
    return fresh_registry.load_all(reqscript)
end

---Runs DwarfUI validation or its explicit development reload command.
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
