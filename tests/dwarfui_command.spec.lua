local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Creates a minimal valid registry generation for command testing.
---@param names string[]
---@param generation string
---@param events table[]
---@return table
local function make_registry(names, generation, events)
    local specs = {}
    for _, name in ipairs(names) do
        table.insert(specs, {name=name})
    end
    return {
        MODULES=specs,
        get_script_names=function()
            return {'dwarfui/module_registry', table.unpack(names)}
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
    it('reloads the manifest, modules, and overlays in order', function()
        local events = {}
        local old_names = {
            'dwarfui/context_menu/registration',
            'dwarfui/consumer',
            'dwarfui/dependency',
        }
        local fresh_names = {
            'dwarfui/dependency',
            'dwarfui/context_menu/registration',
            'dwarfui/consumer',
        }
        local old_registry = make_registry(old_names, 'old', events)
        local fresh_registry = make_registry(fresh_names, 'fresh', events)
        local registry = old_registry
        local scripts = {}
        local all_names = {
            'dwarfui/module_registry',
            'dwarfui/context_menu/registration',
            'dwarfui/consumer',
            'dwarfui/dependency',
            'dwarfui-mood-popover',
            'dwarfui-minecart-route-markers',
            'dwarfui-unit-card-task-details',
        }
        for _, name in ipairs(all_names) do
            scripts['/scripts/' .. name .. '.lua'] = {generation='old'}
        end
        local overlay_db = {}
        for _, script in ipairs({
                'dwarfui-mood-popover',
                'dwarfui-minecart-route-markers',
                'dwarfui-unit-card-task-details'}) do
            overlay_db[script .. '.widget'] = {
                widget={
                    overlay_ondisable=function()
                        table.insert(events, {'retire', script})
                    end,
                },
            }
        end
        overlay_db['unrelated.widget'] = {
            widget={
                overlay_ondisable=function()
                    table.insert(events, {'retire', 'unrelated'})
                end,
            },
        }

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
                    if name == 'dwarfui/context_menu/registration' then
                        return {
                            manager={
                                shutdown=function()
                                    table.insert(events,
                                        {'retire', 'context_menu'})
                                end,
                            },
                        }
                    end
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

        assert.same({'retire', 'dwarfui-mood-popover'}, events[1])
        assert.same(
            {'retire', 'dwarfui-minecart-route-markers'}, events[2])
        assert.same(
            {'retire', 'dwarfui-unit-card-task-details'}, events[3])
        assert.same({'retire', 'context_menu'}, events[4])
        assert.same({'clear', 'devel/clear-script-env',
            'dwarfui/context_menu/registration',
            'dwarfui/consumer', 'dwarfui/dependency'}, events[5])
        assert.same({'clear', 'devel/clear-script-env',
            'dwarfui/module_registry'}, events[6])
        assert.same({'run', 'dwarfui/module_registry'}, events[7])
        assert.same({'clear', 'devel/clear-script-env',
            'dwarfui/dependency',
            'dwarfui/context_menu/registration',
            'dwarfui/consumer'}, events[8])
        assert.same({'run', 'dwarfui/dependency'}, events[9])
        assert.same(
            {'run', 'dwarfui/context_menu/registration'}, events[10])
        assert.same({'run', 'dwarfui/consumer'}, events[11])
        assert.same({'overlay_rescan'}, events[12])
        assert.same({'validate', 'fresh'}, events[13])
        assert.is_nil(events[14])
        assert.is_nil(scripts['/scripts/dwarfui-mood-popover.lua'])
        assert.is_nil(scripts[
            '/scripts/dwarfui-minecart-route-markers.lua'])
        assert.is_nil(scripts[
            '/scripts/dwarfui-unit-card-task-details.lua'])
    end)

    it('validates modules without clearing them for the default command',
            function()
        local events = {}
        local registry = make_registry({'dwarfui/text'}, 'current', events)
        local environment = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui.lua', {
                globals={dfhack_flags={module=true}, dfhack={}},
                reqscript=setmetatable({}, {__index=function(_, name)
                    if name == 'dwarfui/module_registry' then return registry end
                    return {wrap_text=function() end}
                end}),
            })

        environment.main()

        assert.same({{'validate', 'current'}}, events)
    end)
end)
