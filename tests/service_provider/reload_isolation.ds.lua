-- Verifies DwarfUI reload against the installed DwarfUICore provider runtime.

local gui = require('gui')

describe('DwarfUI service-provider reload isolation', function()
    it('clears only DwarfUI registrations and preserves Core generation',
            function()
        local core_services = reqscript('dwarfuicore/services')
        local dwarfui_services = reqscript('dwarfui/services')
        local runtime = reqscript('dwarfuicore/service_provider/runtime')
        local other_tooltip =
            core_services.TooltipServiceProvider:new(1, 'dwarfui-test-disposable')
        local other_context =
            core_services.ContextMenuServiceProvider:new(
                1, 'dwarfui-test-disposable')
        local dwarfui_widget = gui.View{}
        local other_widget = gui.View{}
        local definition = {
            entries={{label='Disposable action', on_select=function() end}},
        }

        local ok, failure = xpcall(function()
            assert.is_true(
                dwarfui_services.TooltipService:register(dwarfui_widget))
            assert.is_true(dwarfui_services.ContextMenuService:register(
                dwarfui_widget, definition))
            assert.is_true(other_tooltip:register(other_widget))
            assert.is_true(other_context:register(other_widget, definition))
            local generation = runtime.validate().generation

            dfhack.run_command('dwarfui', 'reload')

            assert.equals(generation, runtime.validate().generation)
            assert.is_false(
                dwarfui_services.TooltipService:unregister(dwarfui_widget))
            assert.is_false(dwarfui_services.ContextMenuService:unregister(
                dwarfui_widget))
            assert.is_true(other_tooltip:unregister(other_widget))
            assert.is_true(other_context:unregister(other_widget))
        end, debug.traceback)

        pcall(function() other_tooltip:clear_namespace() end)
        pcall(function() other_context:clear_namespace() end)
        assert.is_true(ok, failure)
    end)
end)
