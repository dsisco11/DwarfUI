local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local module_path =
    'src/scripts_modinstalled/dwarfui/widgets/hover_action_rail.lua'

---Builds an isolated generic hover-action rail module context.
---@return table
local function make_context()
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    local _, module = module_loader.load(repo_root, module_path, {
        globals={
            DEFAULT_NIL=default_nil,
            defclass=widget_harness.defclass,
        },
        require_modules={['gui.widgets']=widgets},
    })
    return {
        HoverAction=module.HoverAction,
        HoverActionRail=module.HoverActionRail,
        HoverActionTarget=module.HoverActionTarget,
        widgets=widgets,
    }
end

---Builds one valid action definition for a test rail.
---@param context table
---@param values? table
---@return dwarfui.HoverAction
local function action(context, values)
    values = values or {}
    return context.HoverAction{
        id=values.id or 'zoom',
        widget_factory=values.widget_factory or function(on_activate)
            return context.widgets.Widget{on_activate=on_activate}
        end,
        activate=values.activate or function() return true end,
        visible=values.visible,
        enabled=values.enabled,
        gap_after=values.gap_after,
    }
end

---Builds the required generic providers for one test rail.
---@param values? table
---@return table
local function rail_options(values)
    values = values or {}
    return {
        actions=values.actions,
        target_at=values.target_at or function() return nil end,
        validate_target=values.validate_target or function() return nil end,
        context_active=values.context_active or function() return true end,
        mouse_provider=values.mouse_provider or function() return nil, nil end,
        placement_bounds_provider=values.placement_bounds_provider or
            function() return {x1=0, y1=0, x2=79, y2=24} end,
        placement_order=values.placement_order,
        action_gap=values.action_gap,
        consume_scroll=values.consume_scroll,
        background_pen=values.background_pen,
        border_style=values.border_style,
        content_inset=values.content_inset,
    }
end

---Asserts that a callback raises the expected message fragment.
---@param expected string
---@param callback fun()
local function expect_error(expected, callback)
    local ok, err = pcall(callback)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find(expected, 1, true), tostring(err))
end

describe('DwarfUI HoverActionTarget', function()
    it('snapshots valid opaque target data without interpreting it', function()
        local context = make_context()
        local anchor = {x1=1, y1=2, x2=3, y2=4}
        local payload = {route_id=7, stop_id=9}
        local target = context.HoverActionTarget{
            key='route:7:stop:9',
            anchor=anchor,
            payload=payload,
        }
        anchor.x1 = 99

        assert.same({x1=1, y1=2, x2=3, y2=4}, target.anchor)
        assert.is.equal(payload, target.payload)
    end)

    it('rejects unstable keys and invalid anchor bounds', function()
        local context = make_context()
        for _, key in ipairs({'', 1.5, {}, false}) do
            expect_error('HoverActionTarget.key', function()
                context.HoverActionTarget{
                    key=key,
                    anchor={x1=0, y1=0, x2=0, y2=0},
                }
            end)
        end
        expect_error('anchor.x2 must be greater than or equal to x1', function()
            context.HoverActionTarget{
                key=1,
                anchor={x1=2, y1=0, x2=1, y2=0},
            }
        end)
        expect_error('anchor.y1 must be an integer', function()
            context.HoverActionTarget{
                key=1,
                anchor={x1=0, y1=0.5, x2=1, y2=1},
            }
        end)
    end)
end)

describe('DwarfUI HoverAction', function()
    it('uses documented true defaults for visibility and enabled state', function()
        local context = make_context()
        local definition = action(context)
        local target = context.HoverActionTarget{
            key=1,
            anchor={x1=0, y1=0, x2=0, y2=0},
        }

        assert.is_true(definition.visible(target))
        assert.is_true(definition.enabled(target))
        assert.equals(0, definition.gap_after)
    end)

    it('rejects invalid action contracts', function()
        local context = make_context()
        local valid = {
            id='zoom',
            widget_factory=function() return context.widgets.Widget{} end,
            activate=function() end,
        }
        for field, expected in pairs({
                id='HoverAction.id',
                widget_factory='HoverAction.widget_factory',
                activate='HoverAction.activate',
            }) do
            local values = {}
            for key, value in pairs(valid) do values[key] = value end
            values[field] = false
            expect_error(expected, function()
                context.HoverAction(values)
            end)
        end
        expect_error('HoverAction.gap_after', function()
            context.HoverAction{
                id='zoom',
                widget_factory=valid.widget_factory,
                activate=valid.activate,
                gap_after=-1,
            }
        end)
    end)
end)

describe('DwarfUI HoverActionRail construction', function()
    it('constructs each stable action widget exactly once', function()
        local context = make_context()
        local created, callbacks = 0, {}
        local first = action(context, {
            id='first',
            widget_factory=function(on_activate)
                created = created + 1
                callbacks.first = on_activate
                return context.widgets.Widget{}
            end,
        })
        local second = action(context, {
            id='second',
            widget_factory=function(on_activate)
                created = created + 1
                callbacks.second = on_activate
                return context.widgets.Widget{}
            end,
        })
        local rail = context.HoverActionRail(rail_options{
            actions={first, second},
        })

        assert.equals(2, created)
        assert.equals(2, #rail.action_widgets)
        assert.is_not.equal(rail.action_widgets[1], rail.action_widgets[2])
        rail.activate = function(_, selected)
            assert.is.equal(first, selected)
            return true
        end
        assert.is_true(callbacks.first())
    end)

    it('copies action, placement, and inset configuration', function()
        local context = make_context()
        local definitions = {action(context)}
        local placements = {'left', 'below'}
        local inset = {l=1, t=2, r=3, b=4}
        local rail = context.HoverActionRail(rail_options{
            actions=definitions,
            placement_order=placements,
            content_inset=inset,
            action_gap=2,
            consume_scroll=true,
            background_pen='background',
            border_style='thin',
        })
        definitions[1] = nil
        placements[1] = 'right'
        inset.l = 99

        assert.equals('zoom', rail.actions[1].id)
        assert.same({'left', 'below'}, rail.placement_order)
        assert.same({l=1, t=2, r=3, b=4}, rail.content_inset)
        assert.same({2, true, 'background', 'thin'}, {
            rail.action_gap,
            rail.consume_scroll,
            rail.background_pen,
            rail.border_style,
        })
    end)

    it('rejects missing providers, invalid configurations, duplicates, and nonwidgets',
            function()
        local context = make_context()
        local valid = rail_options{actions={action(context)}}
        for _, field in ipairs({
                'target_at', 'validate_target', 'context_active', 'mouse_provider',
                'placement_bounds_provider'}) do
            local values = {}
            for key, value in pairs(valid) do values[key] = value end
            values[field] = false
            expect_error('HoverActionRail.' .. field, function()
                context.HoverActionRail(values)
            end)
        end
        expect_error('duplicate hover action ID', function()
            context.HoverActionRail(rail_options{actions={
                action(context, {id='same'}),
                action(context, {id='same'}),
            }})
        end)
        expect_error('must be a HoverAction', function()
            context.HoverActionRail(rail_options{actions={{
                id='loose',
                widget_factory=function() return context.widgets.Widget{} end,
                activate=function() end,
                visible=function() return true end,
                enabled=function() return true end,
                gap_after=0,
            }}})
        end)
        expect_error('actions must use contiguous indexes', function()
            context.HoverActionRail(rail_options{actions={
                [2]=action(context),
            }})
        end)
        expect_error('placement_order[1] is invalid', function()
            context.HoverActionRail(rail_options{
                actions={action(context)},
                placement_order={'diagonal'},
            })
        end)
        expect_error('action_gap must be a nonnegative integer', function()
            context.HoverActionRail(rail_options{
                actions={action(context)}, action_gap=1.5,
            })
        end)
        expect_error('consume_scroll must be a boolean', function()
            context.HoverActionRail(rail_options{
                actions={action(context)}, consume_scroll=1,
            })
        end)
        expect_error('content_inset has an invalid edge', function()
            context.HoverActionRail(rail_options{
                actions={action(context)}, content_inset={l=-1},
            })
        end)
        expect_error('background_pen must be false, a callback, or a static value',
                function()
            context.HoverActionRail(rail_options{
                actions={action(context)}, background_pen=true,
            })
        end)
        expect_error('widget_factory must return a widgets.Widget', function()
            context.HoverActionRail(rail_options{actions={action(context, {
                widget_factory=function() return {} end,
            })}})
        end)
    end)
end)
