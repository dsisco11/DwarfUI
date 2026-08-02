local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

describe('DwarfUI service bindings', function()
    it('acquires both exact-major APIs under the DwarfUI namespace', function()
        local calls = {}

        ---Creates a provider double that records each acquisition.
        ---@param kind string
        ---@return table provider
        local function provider(kind)
            return {
                new=function(_, contract_major, namespace)
                    table.insert(calls, {kind, contract_major, namespace})
                    return {
                        kind=kind,
                        clear_namespace=function(self)
                            table.insert(calls, {'clear', self.kind})
                            return self.kind == 'tooltip'
                        end,
                    }
                end,
            }
        end

        local _, services = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/services.lua', {
                reqscript={
                    ['dwarfuicore/services']={
                        TooltipServiceProvider=provider('tooltip'),
                        ContextMenuServiceProvider=provider('context-menu'),
                    },
                },
            })

        assert.same({
            {'tooltip', 1, 'dwarfui'},
            {'context-menu', 1, 'dwarfui'},
        }, calls)
        assert.equals('tooltip', services.TooltipService.kind)
        assert.equals('context-menu', services.ContextMenuService.kind)
        services.refresh()
        assert.is_true(services.clear_namespaces())
        assert.same({
            {'tooltip', 1, 'dwarfui'},
            {'context-menu', 1, 'dwarfui'},
            {'tooltip', 1, 'dwarfui'},
            {'context-menu', 1, 'dwarfui'},
            {'clear', 'tooltip'},
            {'clear', 'context-menu'},
        }, calls)
    end)

    it('keeps the previous coherent pair when refresh fails', function()
        local fail_context = false
        local sequence = 0

        ---Creates one generation-labeled service API double.
        ---@param kind string
        ---@return table api
        local function make_api(kind)
            sequence = sequence + 1
            return {kind=kind, sequence=sequence}
        end

        local _, services = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/services.lua', {
                reqscript={
                    ['dwarfuicore/services']={
                        TooltipServiceProvider={
                            new=function() return make_api('tooltip') end,
                        },
                        ContextMenuServiceProvider={
                            new=function()
                                if fail_context then error('context unavailable') end
                                return make_api('context-menu')
                            end,
                        },
                    },
                },
            })
        local old_tooltip = services.TooltipService
        local old_context = services.ContextMenuService
        fail_context = true

        local ok = pcall(services.refresh)

        assert.is_false(ok)
        assert.is_equal(old_tooltip, services.TooltipService)
        assert.is_equal(old_context, services.ContextMenuService)
    end)

    it('attempts both namespace removals before surfacing a removal failure',
            function()
        local calls = {}
        local _, services = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/services.lua', {
                reqscript={
                    ['dwarfuicore/services']={
                        TooltipServiceProvider={new=function()
                            return {clear_namespace=function()
                                table.insert(calls, 'tooltip')
                                error('stale tooltip API')
                            end}
                        end},
                        ContextMenuServiceProvider={new=function()
                            return {clear_namespace=function()
                                table.insert(calls, 'context-menu')
                                return true
                            end}
                        end},
                    },
                },
            })

        assert.has_error(function() services.clear_namespaces() end,
            'stale tooltip API')
        assert.same({'tooltip', 'context-menu'}, calls)
    end)
end)
