local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local function load_module()
    local _, immutable_enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/utils/immutable_enum.lua')
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/ui_hotkeys.lua', {
            globals={
                defclass=widget_harness.defclass,
                DEFAULT_NIL=widget_harness.default_nil(),
            },
            reqscript={
                ['dwarfui/utils/immutable_enum']=immutable_enum,
            },
        })
    return module
end

describe('DwarfUI UI hotkeys model', function()
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
                action_binding='D_CITIZEN',
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
                if action_binding == 'D_CITIZEN' then return 'u' end
                return nil
            end,
            button_catalog={
                {
                    menu_id=hotkeys.UiHotkeyMenuId.CITIZENS,
                    semantic_id='citizens',
                    action_binding='D_CITIZEN',
                    bounds_finder=function()
                        return {x1=10, y1=30, x2=15, y2=33}
                    end,
                },
                {
                    menu_id=hotkeys.UiHotkeyMenuId.MILITARY,
                    semantic_id='military',
                    action_binding='D_MILITARY',
                    bounds_finder=function()
                        return {x1=16, y1=30, x2=21, y2=33}
                    end,
                },
                {
                    menu_id=hotkeys.UiHotkeyMenuId.SQUADS,
                    semantic_id='squads',
                    action_binding='D_SQUADS',
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
                action_binding='D_CITIZEN',
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
