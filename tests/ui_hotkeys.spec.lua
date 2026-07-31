local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

---@param globals? table
---@return table
local function load_module(globals)
    local _, immutable_enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/utils/immutable_enum.lua')
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/ui_hotkeys.lua', {
            globals={
                defclass=widget_harness.defclass,
                DEFAULT_NIL=widget_harness.default_nil(),
                df=globals and globals.df,
                dfhack=globals and globals.dfhack,
            },
            reqscript={
                ['dwarfui/utils/immutable_enum']=immutable_enum,
            },
        })
    return module
end

describe('DwarfUI UI hotkeys model', function()
    it('resolves the current Citizen hotkey through the interface-key enum',
            function()
        local hotkeys = load_module({
            df={interface_key={D_UNITLIST=17}},
            dfhack={screen={
                getKeyDisplay=function(interface_key)
                    assert.equals(17, interface_key)
                    return 'u'
                end,
            }},
        })
        local model = hotkeys.UiHotkeyModel{
            active_provider=function() return true end,
            dimensions_provider=function() return 80, 25 end,
            button_catalog={{
                menu_id=hotkeys.UiHotkeyMenuId.CITIZENS,
                semantic_id='citizens',
                action_binding='D_UNITLIST',
                bounds_finder=function()
                    return {x1=1, y1=20, x2=8, y2=23}
                end,
            }},
        }

        local snapshot = model:build_snapshot()
        assert.equals(1, #snapshot.buttons)
        assert.equals('u', snapshot.buttons[1].label)
    end)

    it('extracts each button from one dynamically sized native button group',
            function()
        local hotkeys = load_module()
        local width, height = 100, 30
        local button_rects = {
            {x1=13, y1=26, x2=17, y2=29},
            {x1=18, y1=26, x2=22, y2=29},
            {x1=23, y1=26, x2=27, y2=29},
            {x1=28, y1=26, x2=32, y2=29},
            {x1=33, y1=26, x2=37, y2=29},
            {x1=38, y1=26, x2=42, y2=29},
            {x1=43, y1=26, x2=47, y2=29},
            {x1=48, y1=26, x2=52, y2=29},
        }
        local function in_rect(x, y, rect)
            return x >= rect.x1 and x <= rect.x2 and
                y >= rect.y1 and y <= rect.y2
        end
        local model = hotkeys.UiHotkeyModel{
            active_provider=function() return true end,
            dimensions_provider=function() return width, height end,
            read_tile=function(x, y)
                for _, rect in ipairs(button_rects) do
                    if in_rect(x, y, rect) then
                        return {tile=1, ch=0, write_to_lower=true}
                    end
                end
                return {tile=0, ch=32, write_to_lower=false}
            end,
            binding_lookup=function(action_binding)
                if action_binding == 'D_UNITLIST' then return 'u' end
                return nil
            end,
        }

        local snapshot = model:build_snapshot()
        assert.is_true(snapshot.active)
        assert.equals(1, #snapshot.buttons)
        assert.equals('citizens', snapshot.buttons[1].semantic_id)
        assert.equals('D_UNITLIST', snapshot.buttons[1].action_binding)
        assert.same(button_rects[1], snapshot.buttons[1].bounds)
        assert.equals('u', snapshot.buttons[1].label)
    end)

    it('re-queries native bounds when the group moves at the same resolution',
            function()
        local hotkeys = load_module()
        local origin = 4
        local model = hotkeys.UiHotkeyModel{
            active_provider=function() return true end,
            dimensions_provider=function() return 100, 30 end,
            read_tile=function(x, y)
                local filled = x >= origin and x < origin + 40 and
                    y >= 26 and y <= 29
                return filled and
                    {tile=1, ch=0, write_to_lower=true} or
                    {tile=0, ch=32, write_to_lower=false}
            end,
            binding_lookup=function(action_binding)
                return action_binding == 'D_UNITLIST' and 'u' or nil
            end,
        }

        local first = model:build_snapshot()
        assert.same({x1=4, y1=26, x2=8, y2=29},
            first.buttons[1].bounds)

        origin = 20
        local second = model:build_snapshot()
        assert.same({x1=20, y1=26, x2=24, y2=29},
            second.buttons[1].bounds)
        assert.not_equals(first.layout_signature, second.layout_signature)
    end)

    it('recomputes bounds across window-size layout drift', function()
        local hotkeys = load_module()
        local width, height = 80, 25
        local sample_calls = 0
        local model = hotkeys.UiHotkeyModel{
            active_provider=function() return true end,
            dimensions_provider=function() return width, height end,
            binding_lookup=function() return 'u' end,
            button_catalog={{
                menu_id=hotkeys.UiHotkeyMenuId.CITIZENS,
                semantic_id='citizens',
                action_binding='D_UNITLIST',
                bounds_finder=function(context)
                    sample_calls = sample_calls + 1
                    return {
                        x1=context.width - 8,
                        y1=context.height - 4,
                        x2=context.width - 3,
                        y2=context.height - 2,
                    }
                end,
            }},
        }

        local first = model:build_snapshot()
        assert.same({x1=72, y1=21, x2=77, y2=23}, first.buttons[1].bounds)
        assert.equals(1, sample_calls)

        width, height = 96, 30
        local second = model:build_snapshot()
        assert.same({x1=88, y1=26, x2=93, y2=28}, second.buttons[1].bounds)
        assert.equals(2, sample_calls)
    end)

    it('caches sampled bounds until the layout signature changes', function()
        local hotkeys = load_module()
        local sample_calls = 0
        local signature = 'A'
        local model = hotkeys.UiHotkeyModel{
            active_provider=function() return true end,
            dimensions_provider=function() return 80, 25 end,
            layout_signature_provider=function() return signature end,
            binding_lookup=function() return 'u' end,
            button_catalog={{
                menu_id=hotkeys.UiHotkeyMenuId.CITIZENS,
                semantic_id='citizens',
                action_binding='D_UNITLIST',
                bounds_finder=function()
                    sample_calls = sample_calls + 1
                    return {x1=1, y1=2, x2=3, y2=4}
                end,
            }},
        }

        local first = model:build_snapshot()
        local second = model:build_snapshot()
        assert.equals(1, sample_calls)
        assert.equals(1, #first.buttons)
        assert.equals(1, #second.buttons)

        signature = 'B'
        local third = model:build_snapshot()
        assert.equals(2, sample_calls)
        assert.equals('80x25|B', third.layout_signature)
    end)

    it('suppresses only buttons missing bounds or resolved labels', function()
        local hotkeys = load_module()
        local model = hotkeys.UiHotkeyModel{
            active_provider=function() return true end,
            dimensions_provider=function() return 120, 40 end,
            binding_lookup=function(action_binding)
                if action_binding == 'D_UNITLIST' then return 'u' end
                return nil
            end,
            button_catalog={
                {
                    menu_id=hotkeys.UiHotkeyMenuId.CITIZENS,
                    semantic_id='citizens',
                    action_binding='D_UNITLIST',
                    bounds_finder=function()
                        return {x1=10, y1=30, x2=15, y2=33}
                    end,
                },
                {
                    menu_id=hotkeys.UiHotkeyMenuId.TASKS,
                    semantic_id='tasks',
                    action_binding='D_JOBLIST',
                    bounds_finder=function()
                        return {x1=16, y1=30, x2=21, y2=33}
                    end,
                },
                {
                    menu_id=hotkeys.UiHotkeyMenuId.PLACES,
                    semantic_id='places',
                    action_binding='D_LOCATIONS',
                    bounds_finder=function() return nil end,
                },
            },
        }

        local snapshot = model:build_snapshot()
        assert.is_true(snapshot.active)
        assert.equals(1, #snapshot.buttons)
        assert.equals('citizens', snapshot.buttons[1].semantic_id)
        assert.equals('u', snapshot.buttons[1].label)
    end)

    it('normalizes key display values to compact corner-label tokens', function()
        local hotkeys = load_module()
        assert.equals('u', hotkeys.normalize_hotkey_label('Shift-U'))
        assert.equals('F1', hotkeys.normalize_hotkey_label('Alt+F1'))
        assert.equals('9', hotkeys.normalize_hotkey_label('Ctrl+9'))
        assert.equals('=', hotkeys.normalize_hotkey_label('= Equals'))
        assert.is_nil(hotkeys.normalize_hotkey_label('   '))
        assert.is_nil(hotkeys.normalize_hotkey_label(nil))
    end)

    it('clears cached geometry whenever the model becomes inactive', function()
        local hotkeys = load_module()
        local active = true
        local sample_calls = 0
        local model = hotkeys.UiHotkeyModel{
            active_provider=function() return active end,
            dimensions_provider=function() return 80, 25 end,
            binding_lookup=function() return 'u' end,
            button_catalog={{
                menu_id=hotkeys.UiHotkeyMenuId.CITIZENS,
                semantic_id='citizens',
                action_binding='D_UNITLIST',
                bounds_finder=function()
                    sample_calls = sample_calls + 1
                    return {x1=1, y1=2, x2=3, y2=4}
                end,
            }},
        }

        model:build_snapshot()
        assert.equals(1, sample_calls)

        active = false
        local inactive_snapshot = model:build_snapshot()
        assert.is_false(inactive_snapshot.active)
        assert.equals(0, #inactive_snapshot.buttons)

        active = true
        model:build_snapshot()
        assert.equals(2, sample_calls)
    end)
end)
