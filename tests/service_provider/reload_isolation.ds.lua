-- Verifies DwarfUI reload against the installed DwarfUICore provider runtime.

local gui = require('gui')

describe('DwarfUI service-provider reload isolation', function()
    it('restores DwarfUI after a Core reload without clearing another namespace',
            function()
        local other_tooltip
        local other_context
        local dwarfui_widget = gui.View{}
        local other_widget = gui.View{}
        local definition = {
            entries={{label='Disposable action', on_select=function() end}},
        }

        local ok, failure = xpcall(function()
            dfhack.run_command('dwarfui', 'reload')
            local core_services = reqscript('dwarfuicore/services')
            local dwarfui_services = reqscript('dwarfui/services')
            other_tooltip = core_services.TooltipServiceProvider:new(1,
                'dwarfui-test-disposable')
            other_context = core_services.ContextMenuServiceProvider:new(1,
                'dwarfui-test-disposable')
            assert.is_true(
                dwarfui_services.TooltipService:register(dwarfui_widget))
            assert.is_true(dwarfui_services.ContextMenuService:register(
                dwarfui_widget, definition))
            assert.is_true(other_tooltip:register(other_widget))
            assert.is_true(other_context:register(other_widget, definition))
            dfhack.run_command('dwarfuicore', 'reload')
            local refreshed_core = reqscript('dwarfuicore/services')
            local fresh_other = refreshed_core.TooltipServiceProvider:new(1,
                'dwarfui-test-disposable')
            local fresh_context = refreshed_core.ContextMenuServiceProvider:new(
                1, 'dwarfui-test-disposable')
            assert.is_true(fresh_other:register(other_widget))
            assert.is_true(fresh_context:register(other_widget, definition))
            dfhack.run_command('dwarfui', 'reload')

            local refreshed_services = reqscript('dwarfui/services')
            assert.is_false(
                refreshed_services.TooltipService:unregister(dwarfui_widget))
            assert.is_false(refreshed_services.ContextMenuService:unregister(
                dwarfui_widget))
            assert.is_true(fresh_other:unregister(other_widget))
            assert.is_true(fresh_context:unregister(other_widget))
            assert.is_number(reqscript('dwarfuicore/service_provider/runtime')
                .validate().generation)
        end, debug.traceback)

        pcall(function() other_tooltip:clear_namespace() end)
        pcall(function() other_context:clear_namespace() end)
        assert.is_true(ok, failure)
    end)
end)
