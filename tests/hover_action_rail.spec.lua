local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local dwarfuicore_root = require('support.dwarfuicore_root')
local widget_harness = require('support.widget_harness')
local stub = require('luassert.stub')

local module_path =
    'src/scripts_modinstalled/dwarfui/widgets/hover_action_rail.lua'
local _, class_helpers = module_loader.load(dwarfuicore_root,
    'src/scripts_modinstalled/dwarfuicore/class.lua')

---Builds an isolated generic hover-action rail module context.
---@return table
local function make_context()
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, enabled=true, disabled=false}
    local parsed_backgrounds = {}
    local gui = {
        FRAME_THIN='thin',
        FRAME_INTERIOR='interior',
        FRAME_INTERIOR_MEDIUM='interior_medium',
        paint_frame=function(dc, rect, style)
            table.insert(dc.events, {kind='border', rect=rect, style=style})
        end,
    }
    local _, module = module_loader.load(repo_root, module_path, {
        globals={
            DEFAULT_NIL=default_nil,
            defclass=widget_harness.defclass,
            dfhack={pen={parse=function(value)
                table.insert(parsed_backgrounds, value)
                return {parsed=value}
            end}},
        },
        require_modules={gui=gui, ['gui.widgets']=widgets},
        reqscript={['dwarfuicore/class']=class_helpers},
    })
    return {
        HoverAction=module.HoverAction,
        HoverActionRail=module.HoverActionRail,
        HoverActionTarget=module.HoverActionTarget,
        gui=gui,
        parsed_backgrounds=parsed_backgrounds,
        widgets=widgets,
    }
end

---Builds a valid target for rail presentation tests.
---@param context table
---@param key? string|integer
---@return dwarfui.HoverActionTarget
local function target(context, key)
    return context.HoverActionTarget{
        key=key or 'target',
        anchor={x1=5, y1=6, x2=9, y2=6},
        payload={name='opaque'},
    }
end

---Builds a painter that records ordered surface and action rendering.
---@return table
local function painter()
    local result = {events={}}
    function result:fill(rect, pen)
        table.insert(self.events, {kind='background', rect=rect, pen=pen})
    end
    return result
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
        validate_target=values.validate_target or function(current_target)
            return current_target
        end,
        context_active=values.context_active or function() return true end,
        placement_bounds_provider=values.placement_bounds_provider or
            function() return {x1=0, y1=0, x2=79, y2=24} end,
        placement_order=values.placement_order,
        action_gap=values.action_gap,
        target_gap=values.target_gap,
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
                'target_at', 'validate_target', 'context_active',
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
        expect_error('target_gap must be a nonnegative integer', function()
            context.HoverActionRail(rail_options{
                actions={action(context)}, target_gap=-1,
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

describe('DwarfUI HoverActionRail surface', function()
    it('keeps the full-parent controller transparent and hides its surface without a target',
            function()
        local context = make_context()
        local rail = context.HoverActionRail(rail_options{
            actions={action(context)},
        })

        assert.same({l=0, t=0, r=0, b=0}, rail.frame)
        assert.equals(1, #rail.subviews)
        assert.is.equal(rail.surface, rail.subviews[1])
        assert.is.equal(rail.action_widgets[1], rail.surface.subviews[1])
        assert.is_false(rail.surface.visible)
        assert.is_false(rail.action_widgets[1].visible)
        assert.is_nil(rail.rail_bounds)

        rail.active_target = target(context)
        rail:refresh_surface()
        rail.active_target = nil
        rail:refresh_surface()

        assert.is_false(rail.surface.visible)
        assert.is_false(rail.action_widgets[1].visible)
        assert.is_false(rail.action_widgets[1].enabled)
        assert.is_nil(rail.rail_bounds)
    end)

    it('applies transparent, static, and target-sensitive backgrounds only for the current target',
            function()
        local context = make_context()
        local seen_key
        local rail = context.HoverActionRail(rail_options{
            actions={action(context)},
            background_pen=function(current_target)
                seen_key = current_target.key
                return {keep_lower=true, fg='yellow'}
            end,
        })
        rail:refresh_surface()
        assert.equals(0, #context.parsed_backgrounds)

        rail.active_target = target(context, 'current')
        rail:refresh_surface()
        assert.equals('current', seen_key)
        assert.same({parsed={keep_lower=true, fg='yellow'}},
            rail.surface.frame_background)
        assert.same({{keep_lower=true, fg='yellow'}}, context.parsed_backgrounds)

        local transparent = context.HoverActionRail(rail_options{
            actions={action(context)}, background_pen=false,
        })
        transparent.active_target = target(context)
        transparent:refresh_surface()
        assert.is_false(transparent.surface.frame_background)

        local static = context.HoverActionRail(rail_options{
            actions={action(context)}, background_pen='opaque',
        })
        static.active_target = target(context)
        static:refresh_surface()
        assert.same({parsed='opaque'}, static.surface.frame_background)
        assert.same({
            {keep_lower=true, fg='yellow'},
            'opaque',
        }, context.parsed_backgrounds)
    end)

    it('supports frameless, standard, custom, and target-sensitive borders',
            function()
        local context = make_context()
        local custom = {tl='[', t='=', tr=']', pen='cyan'}
        local seen_key
        local rail = context.HoverActionRail(rail_options{
            actions={action(context)},
            border_style=function(current_target)
                seen_key = current_target.key
                return custom
            end,
        })
        rail.active_target = target(context, 42)
        rail:refresh_surface()
        assert.equals(42, seen_key)
        assert.is.equal(custom, rail.surface.frame_style)

        local frameless = context.HoverActionRail(rail_options{
            actions={action(context)}, border_style=false,
        })
        frameless.active_target = target(context)
        frameless:refresh_surface()
        assert.is_false(frameless.surface.frame_style)

        for _, style in ipairs({
                context.gui.FRAME_THIN,
                context.gui.FRAME_INTERIOR,
                context.gui.FRAME_INTERIOR_MEDIUM,
            }) do
            local standard = context.HoverActionRail(rail_options{
                actions={action(context)}, border_style=style,
            })
            standard.active_target = target(context)
            standard:refresh_surface()
            assert.equals(style, standard.surface.frame_style)
        end
    end)

    it('uses scalar and asymmetric insets while compacting visible action widgets',
            function()
        local context = make_context()
        local created = 0
        local first = action(context, {
            id='first',
            gap_after=1,
            widget_factory=function()
                created = created + 1
                return context.widgets.Widget{frame={w=2, h=1}}
            end,
        })
        local second_visible = false
        local second = action(context, {
            id='second',
            widget_factory=function()
                created = created + 1
                return context.widgets.Widget{frame={w=3, h=2}}
            end,
            visible=function() return second_visible end,
            enabled=function() return false end,
        })
        local rail = context.HoverActionRail(rail_options{
            actions={first, second},
            action_gap=2,
            content_inset={l=1, t=2, r=3, b=4},
        })
        rail.active_target = target(context)
        rail:refresh_surface()
        assert.equals(2, created)
        assert.same({0, 0, 2, 1}, {
            rail.action_widgets[1].frame.l,
            rail.action_widgets[1].frame.t,
            rail.action_widgets[1].frame.w,
            rail.action_widgets[1].frame.h,
        })
        assert.is_false(rail.action_widgets[2].visible)
        assert.same({6, 7}, {rail.surface.frame.w, rail.surface.frame.h})
        assert.same({10, 3, 15, 9}, {
            rail.rail_bounds.x1,
            rail.rail_bounds.y1,
            rail.rail_bounds.x2,
            rail.rail_bounds.y2,
        })

        second_visible = true
        rail:refresh_surface()
        assert.equals(2, created)
        assert.is_true(rail.action_widgets[2].visible)
        assert.is_false(rail.action_widgets[2].enabled)
        assert.same({5, 0}, {
            rail.action_widgets[2].frame.l,
            rail.action_widgets[2].frame.t,
        })
        assert.same({12, 8}, {rail.surface.frame.w, rail.surface.frame.h})

        local scalar = context.HoverActionRail(rail_options{
            actions={action(context, {widget_factory=function()
                return context.widgets.Widget{frame={w=2, h=1}}
            end})},
            content_inset=2,
        })
        scalar.active_target = target(context)
        scalar:refresh_surface()
        assert.same({6, 5}, {scalar.surface.frame.w, scalar.surface.frame.h})
    end)

    it('renders background, border, and action widgets in deterministic order',
            function()
        local context = make_context()
        local rail = context.HoverActionRail(rail_options{
            actions={action(context, {widget_factory=function()
                return context.widgets.Widget{
                    frame={w=1, h=1},
                    onRenderFrame=function(_, dc)
                        table.insert(dc.events, {kind='action'})
                    end,
                }
            end})},
            background_pen='opaque',
            border_style=context.gui.FRAME_INTERIOR,
            content_inset=1,
        })
        stub(rail, 'getMousePos', 5, 6)
        rail.active_target = target(context)
        rail:refresh_surface()
        rail:updateLayout(widget_harness.rect(0, 0, 20, 10))
        local dc = painter()
        rail:render(dc)

        assert.same({'background', 'border', 'action'}, {
            dc.events[1].kind,
            dc.events[2].kind,
            dc.events[3].kind,
        })
        assert.is.equal(rail.surface.frame_rect, dc.events[1].rect)
        assert.is.equal(rail.surface.frame_rect, dc.events[2].rect)
    end)

    it('rejects invalid target-sensitive presentation and action-state results',
            function()
        local context = make_context()
        local invalid_background = context.HoverActionRail(rail_options{
            actions={action(context)},
            background_pen=function() return true end,
        })
        invalid_background.active_target = target(context)
        expect_error('background_pen callback returned an invalid presentation value',
            function() invalid_background:refresh_surface() end)

        local invalid_visible = context.HoverActionRail(rail_options{
            actions={action(context, {visible=function() return 'yes' end})},
        })
        invalid_visible.active_target = target(context)
        expect_error('HoverAction.visible must return a boolean',
            function() invalid_visible:refresh_surface() end)
    end)

    it('reuses action widgets when target-sensitive presentation changes',
            function()
        local context = make_context()
        local background = 'first'
        local border = context.gui.FRAME_THIN
        local rail = context.HoverActionRail(rail_options{
            actions={action(context, {widget_factory=function()
                return context.widgets.Widget{frame={w=2, h=1}}
            end})},
            background_pen=function() return background end,
            border_style=function() return border end,
        })
        rail.active_target = target(context, 'first')
        rail:refresh_surface()
        local widget = rail.action_widgets[1]
        background = 'second'
        border = context.gui.FRAME_INTERIOR_MEDIUM
        rail.active_target = target(context, 'second')
        rail:refresh_surface()

        assert.is.equal(widget, rail.action_widgets[1])
        assert.same({parsed='second'}, rail.surface.frame_background)
        assert.equals(context.gui.FRAME_INTERIOR_MEDIUM,
            rail.surface.frame_style)
    end)
end)

describe('DwarfUI HoverActionRail placement', function()
    ---Builds a visible two-action rail with mixed dimensions.
    ---@param context table
    ---@param placement_order string[]
    ---@param bounds table
    ---@return dwarfui.HoverActionRail
    local function mixed_rail(context, placement_order, bounds)
        local first = action(context, {
            id='first',
            gap_after=1,
            widget_factory=function()
                return context.widgets.Widget{frame={w=2, h=1}}
            end,
        })
        local second = action(context, {
            id='second',
            widget_factory=function()
                return context.widgets.Widget{frame={w=3, h=3}}
            end,
        })
        return context.HoverActionRail(rail_options{
            actions={first, second},
            action_gap=1,
            placement_order=placement_order,
            placement_bounds_provider=function() return bounds end,
            content_inset=1,
        })
    end

    ---Builds a target whose anchor is already in rail-local coordinates.
    ---@param context table
    ---@param anchor table
    ---@return dwarfui.HoverActionTarget
    local function anchored_target(context, anchor)
        return context.HoverActionTarget{
            key='anchor',
            anchor=anchor,
        }
    end

    it('places every direction exactly and preserves the nearest action order',
            function()
        local cases = {
            left={surface={1, 9, 9, 13}, actions={5, 1, 0, 0}},
            right={surface={13, 9, 21, 13}, actions={0, 1, 4, 0}},
            above={surface={7, 5, 15, 9}, actions={0, 1, 4, 0}},
            below={surface={7, 13, 15, 17}, actions={0, 1, 4, 0}},
        }
        for placement, expected in pairs(cases) do
            local context = make_context()
            local rail = mixed_rail(context, {placement},
                {x1=0, y1=0, x2=29, y2=29})
            rail.active_target = anchored_target(context,
                {x1=10, y1=10, x2=12, y2=12})
            rail:refresh_surface()

            assert.equals(placement, rail.placement)
            assert.same(expected.surface, {
                rail.rail_bounds.x1,
                rail.rail_bounds.y1,
                rail.rail_bounds.x2,
                rail.rail_bounds.y2,
            })
            assert.is_true(rail.rail_bounds.x1 >= 0)
            assert.is_true(rail.rail_bounds.y1 >= 0)
            assert.is_true(rail.rail_bounds.x2 <= 29)
            assert.is_true(rail.rail_bounds.y2 <= 29)
            assert.same(expected.actions, {
                rail.action_widgets[1].frame.l,
                rail.action_widgets[1].frame.t,
                rail.action_widgets[2].frame.l,
                rail.action_widgets[2].frame.t,
            })
            if placement == 'left' then
                assert.is_true(rail.action_widgets[1].frame.l >
                    rail.action_widgets[2].frame.l)
            elseif placement == 'right' then
                assert.is_true(rail.action_widgets[1].frame.l <
                    rail.action_widgets[2].frame.l)
            end
        end
    end)

    it('tries placement order without clamping across the target or bounds',
            function()
        local context = make_context()
        local rail = mixed_rail(context, {'left', 'right'},
            {x1=0, y1=0, x2=29, y2=29})
        rail.active_target = anchored_target(context,
            {x1=0, y1=10, x2=2, y2=12})
        rail:refresh_surface()
        assert.equals('right', rail.placement)
        assert.same({3, 9, 11, 13}, {
            rail.rail_bounds.x1,
            rail.rail_bounds.y1,
            rail.rail_bounds.x2,
            rail.rail_bounds.y2,
        })
        assert.is_true(rail.rail_bounds.x1 > rail.active_target.anchor.x2)

        local no_fit = mixed_rail(context, {'left', 'right', 'above', 'below'},
            {x1=9, y1=9, x2=13, y2=13})
        no_fit.active_target = anchored_target(context,
            {x1=10, y1=10, x2=12, y2=12})
        no_fit:refresh_surface()
        assert.is_false(no_fit.surface.visible)
        assert.is_nil(no_fit.placement)
        assert.is_nil(no_fit.rail_bounds)
    end)

    it('fits adjacent rails at each placement-bound edge without clipping',
            function()
        local cases = {
            {placement='right', anchor={x1=0, y1=2, x2=0, y2=2},
                bounds={1, 2, 1, 2}},
            {placement='left', anchor={x1=4, y1=2, x2=4, y2=2},
                bounds={3, 2, 3, 2}},
            {placement='below', anchor={x1=2, y1=0, x2=2, y2=0},
                bounds={2, 1, 2, 1}},
            {placement='above', anchor={x1=2, y1=4, x2=2, y2=4},
                bounds={2, 3, 2, 3}},
        }
        for _, case in ipairs(cases) do
            local context = make_context()
            local rail = context.HoverActionRail(rail_options{
                actions={action(context, {widget_factory=function()
                    return context.widgets.Widget{frame={w=1, h=1}}
                end})},
                placement_order={case.placement},
                placement_bounds_provider=function()
                    return {x1=0, y1=0, x2=4, y2=4}
                end,
            })
            rail.active_target = anchored_target(context, case.anchor)
            rail:refresh_surface()
            assert.same(case.bounds, {
                rail.rail_bounds.x1,
                rail.rail_bounds.y1,
                rail.rail_bounds.x2,
                rail.rail_bounds.y2,
            })
        end
    end)

    it('keeps ordered actions stable as additional outward actions are added',
            function()
        local context = make_context()
        local make_action = function(id, width)
            return action(context, {id=id, widget_factory=function()
                return context.widgets.Widget{frame={w=width, h=1}}
            end})
        end
        local rail = context.HoverActionRail(rail_options{
            actions={
                make_action('first', 2),
                make_action('second', 3),
                make_action('third', 1),
            },
            placement_order={'left'},
            placement_bounds_provider=function()
                return {x1=0, y1=0, x2=29, y2=29}
            end,
        })
        rail.active_target = anchored_target(context,
            {x1=10, y1=10, x2=10, y2=10})
        rail:refresh_surface()

        assert.same({4, 1, 0}, {
            rail.action_widgets[1].frame.l,
            rail.action_widgets[2].frame.l,
            rail.action_widgets[3].frame.l,
        })
        assert.same({4, 9}, {
            rail.rail_bounds.x1,
            rail.rail_bounds.x2,
        })
        assert.equals(rail.active_target.anchor.x1 - 1,
            rail.rail_bounds.x1 + rail.action_widgets[1].frame.l +
                rail.action_widgets[1].frame.w - 1)
    end)

    it('uses inherited widget-local pointer coordinates without converting them',
            function()
        local context = make_context()
        local mouse_x, mouse_y = 4, 6
        local resolved_x, resolved_y
        local resolved_target = target(context, 'resolved')
        local rail = context.HoverActionRail(rail_options{
            actions={action(context)},
            target_at=function(x, y)
                resolved_x, resolved_y = x, y
                return resolved_target
            end,
            placement_order={'right'},
            placement_bounds_provider=function()
                return {x1=0, y1=0, x2=19, y2=9}
            end,
        })
        local mouse_stub = stub(rail, 'getMousePos', function()
            return mouse_x, mouse_y
        end)
        rail:updateLayout(widget_harness.rect(10, 20, 20, 10))
        assert.is.equal(resolved_target, rail:resolve_target_at_pointer())
        assert.same({4, 6}, {resolved_x, resolved_y})
        assert.spy(mouse_stub).was.called()

        rail.active_target = anchored_target(context,
            {x1=4, y1=6, x2=4, y2=6})
        rail:refresh_surface()
        assert.same({5, 6, 5, 6}, {
            rail.rail_bounds.x1,
            rail.rail_bounds.y1,
            rail.rail_bounds.x2,
            rail.rail_bounds.y2,
        })
    end)

    it('remeasures visibility, dimensions, insets, and border edges without recreating widgets',
            function()
        local context = make_context()
        local visible = true
        local created = 0
        local rail = context.HoverActionRail(rail_options{
            actions={
                action(context, {widget_factory=function()
                    created = created + 1
                    return context.widgets.Widget{frame={w=2, h=1}}
                end}),
                action(context, {
                    id='conditional',
                    visible=function() return visible end,
                    widget_factory=function()
                        created = created + 1
                        return context.widgets.Widget{frame={w=3, h=2}}
                    end,
                }),
            },
            placement_order={'right'},
            placement_bounds_provider=function()
                return {x1=0, y1=0, x2=29, y2=29}
            end,
            content_inset=1,
            border_style=context.gui.FRAME_THIN,
        })
        rail.active_target = anchored_target(context,
            {x1=10, y1=10, x2=12, y2=12})
        rail:refresh_surface()
        local first_widget, second_widget = rail.action_widgets[1],
            rail.action_widgets[2]
        assert.same({9, 6}, {rail.surface.frame.w, rail.surface.frame.h})

        visible = false
        first_widget.frame.w = 4
        rail.content_inset = {l=2, t=0, r=1, b=3}
        rail:refresh_surface()
        assert.equals(2, created)
        assert.is.equal(first_widget, rail.action_widgets[1])
        assert.is.equal(second_widget, rail.action_widgets[2])
        assert.same({9, 6}, {rail.surface.frame.w, rail.surface.frame.h})
        assert.is_false(second_widget.visible)
    end)

    it('reevaluates anchors, placement bounds, and parent layouts from current state',
            function()
        local context = make_context()
        local bounds = {x1=0, y1=0, x2=29, y2=29}
        local bounds_reads = 0
        local rail = context.HoverActionRail(rail_options{
            actions={action(context, {widget_factory=function()
                return context.widgets.Widget{frame={w=2, h=1}}
            end})},
            placement_order={'right'},
            placement_bounds_provider=function()
                bounds_reads = bounds_reads + 1
                return bounds
            end,
        })
        rail.active_target = anchored_target(context,
            {x1=5, y1=5, x2=5, y2=5})
        rail:refresh_surface()
        assert.same({6, 5}, {rail.rail_bounds.x1, rail.rail_bounds.y1})

        rail.active_target = anchored_target(context,
            {x1=12, y1=8, x2=12, y2=8})
        rail:refresh_surface()
        assert.same({13, 8}, {rail.rail_bounds.x1, rail.rail_bounds.y1})

        bounds = {x1=0, y1=0, x2=13, y2=8}
        rail:refresh_surface()
        assert.is_false(rail.surface.visible)
        local reads_before_layout = bounds_reads
        bounds = {x1=0, y1=0, x2=29, y2=29}
        rail:updateLayout(widget_harness.rect(30, 40, 30, 20))
        assert.is_true(bounds_reads > reads_before_layout)
        assert.is_true(rail.surface.visible)
        assert.same({13, 8}, {rail.rail_bounds.x1, rail.rail_bounds.y1})
    end)

    it('includes border and asymmetric inset edges when centering and fitting',
            function()
        local context = make_context()
        local rail = context.HoverActionRail(rail_options{
            actions={action(context, {widget_factory=function()
                return context.widgets.Widget{frame={w=2, h=1}}
            end})},
            placement_order={'above'},
            border_style=context.gui.FRAME_THIN,
            content_inset={l=2, t=3, r=1, b=0},
            placement_bounds_provider=function()
                return {x1=8, y1=4, x2=14, y2=9}
            end,
        })
        rail.active_target = anchored_target(context,
            {x1=10, y1=10, x2=12, y2=12})
        rail:refresh_surface()

        assert.same({7, 6}, {rail.surface.frame.w, rail.surface.frame.h})
        assert.same({8, 4, 14, 9}, {
            rail.rail_bounds.x1,
            rail.rail_bounds.y1,
            rail.rail_bounds.x2,
            rail.rail_bounds.y2,
        })
    end)

    it('records empty and nonempty retention bridges exactly', function()
        local context = make_context()
        local build = function(target_gap)
            local rail = context.HoverActionRail(rail_options{
                actions={action(context, {widget_factory=function()
                    return context.widgets.Widget{frame={w=2, h=1}}
                end})},
                placement_order={'left'},
                target_gap=target_gap,
                placement_bounds_provider=function()
                    return {x1=0, y1=0, x2=29, y2=29}
                end,
            })
            rail.active_target = anchored_target(context,
                {x1=15, y1=10, x2=15, y2=10})
            rail:refresh_surface()
            return rail
        end
        assert.is_nil(build(0).retention_bridge)
        local spaced = build(2)
        assert.same({13, 10, 14, 10}, {
            spaced.retention_bridge.x1,
            spaced.retention_bridge.y1,
            spaced.retention_bridge.x2,
            spaced.retention_bridge.y2,
        })
    end)
end)

describe('DwarfUI HoverActionRail hover lifecycle', function()
    it('binds, switches, retains across rail and bridge, then clears immediately',
            function()
        local context = make_context()
        local mouse_x, mouse_y = 5, 5
        local context_active, valid = true, true
        local first = context.HoverActionTarget{
            key='first', anchor={x1=5, y1=5, x2=5, y2=5},
        }
        local second = context.HoverActionTarget{
            key='second', anchor={x1=10, y1=5, x2=10, y2=5},
        }
        local rail = context.HoverActionRail(rail_options{
            actions={action(context, {widget_factory=function()
                return context.widgets.Widget{frame={w=1, h=1}}
            end})},
            placement_order={'right'}, target_gap=1,
            context_active=function() return context_active end,
            target_at=function(x, y)
                if y ~= 5 then return nil end
                if x == 5 then return first end
                if x == 10 then return second end
            end,
            validate_target=function(target)
                return valid and target or nil
            end,
        })
        stub(rail, 'getMousePos', function() return mouse_x, mouse_y end)
        rail:updateLayout(widget_harness.rect(0, 0, 30, 15))
        rail:update_hover()
        assert.equals('first', rail:get_target().key)
        assert.same({7, 5, 7, 5}, {
            rail.rail_bounds.x1, rail.rail_bounds.y1,
            rail.rail_bounds.x2, rail.rail_bounds.y2,
        })
        mouse_x = 6 -- bridge cell
        assert.is_false(rail:update_hover())
        assert.equals('first', rail:get_target().key)
        mouse_x = 7 -- rail cell
        assert.is_false(rail:update_hover())
        assert.equals('first', rail:get_target().key)
        mouse_x = 10
        assert.is_true(rail:update_hover())
        assert.equals('second', rail:get_target().key)
        valid = false
        mouse_x = 20
        assert.is_true(rail:update_hover())
        assert.is_nil(rail:get_target())
        assert.is_false(rail.surface.visible)

        valid, mouse_x = true, 5
        rail:update_hover()
        context_active = false
        assert.is_true(rail:update_hover())
        assert.is_nil(rail:get_target())
        assert.is_nil(rail.rail_bounds)
        assert.is_nil(rail.retention_bridge)
    end)
end)

describe('DwarfUI HoverActionRail input', function()
    it('activates only a freshly validated target and rejects stale keys', function()
        local context = make_context()
        local current, called = nil, nil
        local definition = action(context, {activate=function(target)
            called = target
            return true
        end})
        local rail = context.HoverActionRail(rail_options{
            actions={definition},
            validate_target=function() return current end,
        })
        rail.active_target = target(context, 'same')
        current = context.HoverActionTarget{
            key='same', anchor={x1=2, y1=2, x2=2, y2=2}, payload={fresh=true},
        }
        assert.is_true(rail:activate(definition))
        assert.is.equal(current, called)
        assert.is.equal(current, rail:get_target())
        current = context.HoverActionTarget{
            key='other', anchor={x1=2, y1=2, x2=2, y2=2},
        }
        assert.is_false(rail:activate(definition))
        assert.is_nil(rail:get_target())
    end)

    it('owns visible rail clicks and configured wheel input only', function()
        local context = make_context()
        local mouse_x, mouse_y = 5, 5
        local rail = context.HoverActionRail(rail_options{
            actions={action(context, {enabled=function() return false end,
                widget_factory=function() return context.widgets.Widget{frame={w=1,h=1}} end})},
            placement_order={'right'},
            target_at=function(x, y)
                if x == 5 and y == 5 then
                    return context.HoverActionTarget{
                        key='input', anchor={x1=5, y1=5, x2=5, y2=5},
                    }
                end
            end,
            consume_scroll=true,
        })
        stub(rail, 'getMousePos', function() return mouse_x, mouse_y end)
        rail:updateLayout(widget_harness.rect(0, 0, 20, 10))
        rail:update_hover()
        mouse_x = rail.rail_bounds.x1
        assert.is_true(rail:onInput({_MOUSE_L=true}))
        assert.is_true(rail:onInput({CONTEXT_SCROLL_DOWN=true}))
        rail.consume_scroll = false
        assert.is_false(rail:onInput({CONTEXT_SCROLL_DOWN=true}))
        mouse_x = 19
        assert.is_false(rail:onInput({_MOUSE_L=true}))
    end)
end)
