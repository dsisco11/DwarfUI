local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local CONFIG_PATH = 'tests/dwarfspec/config.lua'

---Returns whether a table graph contains a value by identity.
---@param root any
---@param expected any
---@param seen? table<table, boolean>
---@return boolean
local function contains_identity(root, expected, seen)
    if root == expected then return true end
    if type(root) ~= 'table' then return false end
    seen = seen or {}
    if seen[root] then return false end
    seen[root] = true
    for key, value in pairs(root) do
        if contains_identity(key, expected, seen) or
                contains_identity(value, expected, seen) then
            return true
        end
    end
    return false
end

describe('DwarfSpec tooltip diagnostics adapter', function()
    it('adds immutable-value hook and presenter snapshots', function()
        local target = {}
        local intent = {text='Tooltip'}
        local selected_owner = {}
        local overlay_owner = {}
        local screen_owner = {}
        local failed_owner = {}
        local registration_diagnostics = {
            registration_count=1,
            target=target,
            intent=intent,
            poller_generation=7,
        }
        local hook_diagnostics = {
            api_version=1,
            generation=8,
            presenter_installed=true,
            disabled=false,
            current_intent_revision=11,
            failure_count=1,
            last_failure={
                generation=7,
                revision=10,
                transport=2,
                owner=failed_owner,
                error='controlled failure',
            },
            inactive_intent=false,
            selected_transport=2,
            selected_owner=selected_owner,
            render_count=4,
            last_rendered_revision=11,
            last_transport=2,
            overlay={
                owner=overlay_owner,
                tracked=true,
                installed=true,
                outermost=true,
                generation=8,
                repair_count=2,
                chained=true,
            },
            screens={{
                owner=screen_owner,
                tracked=true,
                installed=true,
                outermost=true,
                generation=8,
                repair_count=3,
                chained=true,
                selected=true,
            }},
            screen_hook_count=1,
        }
        local presenter_diagnostics = {
            generation=8,
            active=true,
            current_intent_revision=11,
            service_revision=11,
            selected_transport=2,
            selected_owner=selected_owner,
            supported_surface=true,
            surface_reason='lua-screen',
            last_rendered_revision=11,
            render_count=4,
            redraw_count=5,
        }
        local _, config = module_loader.load(repo_root, CONFIG_PATH, {
            reqscript={
                ['dwarfuicore/tooltip/api']={
                    get_diagnostics=function()
                        local copy = {}
                        for key, value in pairs(registration_diagnostics) do
                            copy[key] = value
                        end
                        copy.presentation = presenter_diagnostics
                        return copy
                    end,
                },
                ['dwarfuicore/tooltip/render_hook']={
                    manager={
                        get_diagnostics=function()
                            return hook_diagnostics
                        end,
                    },
                },
            },
        })

        local result = config.commands.tooltip_state()
        assert.is_equal(target, result.target)
        assert.is_equal(intent, result.intent)
        assert.equals(7, result.poller_generation)
        assert.equals(8, result.presenter.generation)
        assert.is_true(result.presenter.selected_owner_present)
        assert.equals(8, result.render_hook.generation)
        assert.is_true(result.render_hook.selected_owner_present)
        assert.is_true(result.render_hook.overlay.owner_present)
        assert.is_true(result.render_hook.screens[1].owner_present)
        assert.is_true(result.render_hook.last_failure.owner_present)
        for _, implementation_table in ipairs({
                selected_owner,
                overlay_owner,
                screen_owner,
                failed_owner,
                hook_diagnostics.overlay,
                hook_diagnostics.screens[1],
                presenter_diagnostics,
            }) do
            assert.is_false(contains_identity(
                result.render_hook, implementation_table))
            assert.is_false(contains_identity(
                result.presenter, implementation_table))
        end
    end)
end)
