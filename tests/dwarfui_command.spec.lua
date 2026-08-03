local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Creates a valid DwarfUI-only registry generation for command testing.
---@param names string[]
---@param generation string
---@param events table[]
---@param clear_names string[]|nil
---@return table registry
local function make_registry(names, generation, events, clear_names)
    local specs = {}
    for _, name in ipairs(names) do table.insert(specs, {name=name}) end
    return {
        MODULES=specs,
        get_script_names=function()
            return {'dwarfui/module_registry',
                table.unpack(clear_names or names)}
        end,
        load_all=function(loader)
            table.insert(events, {'validate', generation})
            local loaded = {}
            for _, name in ipairs(names) do loaded[name] = loader(name) end
            return loaded
        end,
    }
end

describe('dwarfui command', function()
    it('reloads only DwarfUI-owned modules and overlays', function()
        local events = {}
        local old_registry = make_registry({'dwarfui/consumer'}, 'old', events)
        local fresh_registry = make_registry({'dwarfui/dependency',
            'dwarfui/consumer'}, 'fresh', events)
        local registry = old_registry
        local scripts = {}
        for _, name in ipairs({
                'dwarfui/module_registry', 'dwarfui/consumer',
                'dwarfui/dependency', 'dwarfui-ui-hotkeys',
                'dwarfui-mood-popover', 'dwarfui-minecart-route-markers',
                'dwarfui-unit-card-task-details'}) do
            scripts['/scripts/' .. name .. '.lua'] = {generation='old'}
        end
        local overlay_db = {}
        local services = {
            refresh=function()
                table.insert(events, {'refresh_services', 'dwarfui'})
            end,
            clear_namespaces=function()
                table.insert(events, {'clear_namespaces', 'dwarfui'})
                return true
            end,
        }
        for _, script in ipairs({
                'dwarfui-ui-hotkeys', 'dwarfui-mood-popover',
                'dwarfui-minecart-route-markers',
                'dwarfui-unit-card-task-details'}) do
            overlay_db[script .. '.widget'] = {widget={
                overlay_ondisable=function()
                    table.insert(events, {'retire', script})
                end,
            }}
        end
        local environment = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui.lua', {
                globals={
                    dfhack_flags={module=true},
                    dfhack={
                        internal={scripts=scripts},
                        findScript=function(name)
                            return '/scripts/' .. name .. '.lua'
                        end,
                        run_command=function(...)
                            table.insert(events, {'clear', ...})
                        end,
                        run_script=function(name)
                            table.insert(events, {'run', name})
                            if name == 'dwarfui/module_registry' then
                                registry = fresh_registry
                            end
                        end,
                    },
                },
                reqscript=setmetatable({}, {__index=function(_, name)
                    if name == 'dwarfui/module_registry' then return registry end
                    if name == 'dwarfui/services' then return services end
                    return {generation='fresh'}
                end}),
                require_modules={
                    ['plugins.overlay']={
                        get_state=function() return {db=overlay_db} end,
                        rescan=function()
                            table.insert(events, {'overlay_rescan'})
                        end,
                    },
                },
            })

        environment.reload()

        assert.same({
            {'retire', 'dwarfui-ui-hotkeys'},
            {'retire', 'dwarfui-mood-popover'},
            {'retire', 'dwarfui-minecart-route-markers'},
            {'retire', 'dwarfui-unit-card-task-details'},
            {'refresh_services', 'dwarfui'},
            {'clear_namespaces', 'dwarfui'},
            {'clear', 'devel/clear-script-env', 'dwarfui/consumer'},
            {'clear', 'devel/clear-script-env', 'dwarfui/module_registry'},
            {'run', 'dwarfui/module_registry'},
            {'clear', 'devel/clear-script-env', 'dwarfui/dependency',
                'dwarfui/consumer'},
            {'run', 'dwarfui/dependency'},
            {'run', 'dwarfui/consumer'},
            {'overlay_rescan'},
            {'validate', 'fresh'},
        }, events)
    end)

    it('clears feature-local state before an error from namespace removal',
            function()
        local events = {}
        local overlay_db = {
            ['dwarfui-minecart-route-markers.widget']={widget={
                dwarfui_clear_local_state=function()
                    table.insert(events, 'local')
                end,
                overlay_ondisable=function()
                    error('service-dependent cleanup must not run')
                end,
            }},
        }
        local environment = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui.lua', {
                globals={
                    dfhack_flags={module=true},
                    dfhack={internal={scripts={}}},
                },
                reqscript={
                    ['dwarfui/services']={
                        refresh=function() table.insert(events, 'refresh') end,
                        clear_namespaces=function()
                            table.insert(events, 'clear')
                            error('stale namespace')
                        end,
                    },
                },
                require_modules={
                    ['plugins.overlay']={
                        get_state=function() return {db=overlay_db} end,
                    },
                },
            })

        assert.has_error(function() environment.teardown() end,
            'stale namespace')
        assert.same({'local', 'refresh', 'clear'}, events)
    end)

    it('validates DwarfUI modules without clearing them by default', function()
        local events = {}
        local registry = make_registry({'dwarfui/feature'}, 'current', events)
        local environment = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui.lua', {
                globals={dfhack_flags={module=true}, dfhack={}},
                reqscript=setmetatable({}, {__index=function(_, name)
                    if name == 'dwarfui/module_registry' then return registry end
                    return {}
                end}),
            })

        environment.main()
        assert.same({{'validate', 'current'}}, events)
    end)

    it('retires all hotkey modules in reverse order and reloads them forward',
            function()
        local forward = {
            'dwarfui/hotkeys/geometry',
            'dwarfui/hotkeys/layout_provider',
            'dwarfui/hotkeys/model',
            'dwarfui/hotkeys/groups/fortress_main',
            'dwarfui/hotkeys/groups/fortress_bottom_middle',
            'dwarfui/hotkeys/groups/fortress_bottom_right',
            'dwarfui/hotkeys/overlay',
        }
        local reverse = {}
        for index=#forward,1,-1 do reverse[#reverse + 1] = forward[index] end
        local events = {}
        local old_registry = make_registry(forward, 'old', events, reverse)
        local fresh_registry = make_registry(forward, 'fresh', events)
        local registry = old_registry
        local scripts = {}
        scripts['/scripts/dwarfui/module_registry.lua'] = {}
        for _, name in ipairs(forward) do
            scripts['/scripts/' .. name .. '.lua'] = {}
        end
        for _, name in ipairs({
                'dwarfui-ui-hotkeys', 'dwarfui-mood-popover',
                'dwarfui-minecart-route-markers',
                'dwarfui-unit-card-task-details'}) do
            scripts['/scripts/' .. name .. '.lua'] = {}
        end
        local environment = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui.lua', {
                globals={
                    dfhack_flags={module=true},
                    dfhack={
                        internal={scripts=scripts},
                        findScript=function(name)
                            return '/scripts/' .. name .. '.lua'
                        end,
                        run_command=function(...)
                            events[#events + 1] = {'clear', ...}
                        end,
                        run_script=function(name)
                            events[#events + 1] = {'run', name}
                            if name == 'dwarfui/module_registry' then
                                registry = fresh_registry
                            end
                        end,
                    },
                },
                reqscript=setmetatable({}, {__index=function(_, name)
                    if name == 'dwarfui/module_registry' then return registry end
                    if name == 'dwarfui/services' then
                        return {refresh=function() end,
                            clear_namespaces=function() return false end}
                    end
                    return {}
                end}),
                require_modules={
                    ['plugins.overlay']={
                        get_state=function() return {db={}} end,
                        rescan=function() end,
                    },
                },
            })

        environment.reload()

        local clear_events = {}
        local run_names = {}
        for _, event in ipairs(events) do
            if event[1] == 'clear' then clear_events[#clear_events + 1] = event end
            if event[1] == 'run' and event[2] ~= 'dwarfui/module_registry' then
                run_names[#run_names + 1] = event[2]
            end
        end
        local retired = {}
        for index=3,#clear_events[1] do
            retired[#retired + 1] = clear_events[1][index]
        end
        local refreshed = {}
        for index=3,#clear_events[3] do
            refreshed[#refreshed + 1] = clear_events[3][index]
        end
        assert.same(reverse, retired)
        assert.same(forward, refreshed)
        assert.same(forward, run_names)
    end)
end)
