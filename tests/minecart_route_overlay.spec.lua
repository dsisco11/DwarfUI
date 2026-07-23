local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

---Loads the route-marker overlay with isolated DFHack collaborators.
---@param state table
---@return table
---@return table
local function load_overlay(state)
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets({
        Widget={
            getMousePos=function(self)
                if state.mouse_x == nil or state.mouse_y == nil or
                        not self.frame_body or
                        not self.frame_body:inClipGlobalXY(
                            state.mouse_x, state.mouse_y) then
                    return nil
                end
                return self.frame_body:localXY(state.mouse_x, state.mouse_y)
            end,
        },
    }, default_nil)
    widgets.Widget.ATTRS{
        visible=true,
        enabled=true,
        disabled=false,
        tooltip=default_nil,
    }
    widgets.Label.makeButtonLabelText = function(spec) return spec.chars end
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    local function test_defclass(global_slot, parent)
        return widget_harness.defclass(global_slot, parent or widgets.Widget)
    end
    local selection = {
        selected_route_id=nil,
        clear=function(self) self.selected_route_id = nil end,
        get_selected_route_id=function(self) return self.selected_route_id end,
        resolve_selected_route=function(self, routes)
            return routes and routes[0] or nil
        end,
        observe_input=function(self, keys, x, y, hauling, focus)
            self.input = {keys=keys, x=x, y=y, hauling=hauling, focus=focus}
            self.selected_route_id = hauling.view_routes[0].id
            return false
        end,
    }
    local layout = {
        list_x1=0,
        indicator_x=1,
        first_row_top=10,
        row_height=3,
        cache_bounds=function(self, bounds)
            self.bounds = bounds
            self.list_x1 = bounds.x1
            self.first_row_top = bounds.y1 + 6
        end,
        get_indicator_x=function(self)
            return self.list_x1 + self.indicator_x
        end,
        is_supported_focus=function(_, focus)
            return type(focus) == 'table' and
                focus[1] == 'dwarfmode/Hauling'
        end,
        find_route_header_y=function(_, _, route_id)
            return route_id and 10 or nil
        end,
    }
    local projection = {
        project=function() return state.markers end,
    }
    local _, asset_button = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/widgets/asset_button.lua', {
            globals={
                DEFAULT_NIL=default_nil,
                defclass=widget_harness.defclass,
            },
            require_modules={
                utils={getval=function(value)
                    if type(value) == 'function' then return value() end
                    return value
                end},
                ['gui.widgets']=widgets,
            },
            reqscript={
                ['dwarfui/widget_extensions']={},
            },
        })
    local _, stop_actions = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/minecart_stop_actions.lua', {
            globals={defclass=test_defclass},
            reqscript={
                ['dwarfui/widgets/asset_button']=asset_button,
            },
        })
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui-minecart-route-markers.lua', {
            globals={
                defclass=test_defclass,
                COLOR_YELLOW='yellow',
                df={global={gps={dimy=25}, plotinfo={hauling=state.hauling}}},
                dfhack={
                    gui={
                        getCurFocus=function() return state.focus end,
                        revealInDwarfmodeMap=function(pos, center, highlight)
                            table.insert(state.reveals, {
                                pos=pos,
                                center=center,
                                highlight=highlight,
                            })
                        end,
                    },
                    screen={getMousePos=function() return state.mouse_x,
                        state.mouse_y end,
                        getWindowSize=function() return 264, 75 end,
                        readTile=function() return nil end},
                },
            },
            require_modules={
                ['plugins.overlay']={OverlayWidget=OverlayWidget},
                ['gui.dwarfmode']={
                    Viewport={get=function() return state.viewport end},
                    getPanelLayout=function()
                        return {map={x1=0, y1=0, x2=71, y2=29}}
                    end,
                    renderMapOverlay=function(callback, bounds)
                        table.insert(state.map_calls, {
                            callback=callback, bounds=bounds,
                        })
                        if state.render_events then
                            table.insert(state.render_events, 'map')
                        end
                    end,
                },
            },
            reqscript={
                ['dwarfui/minecart_route']={
                    MinecartRouteMenuLayout=function() return layout end,
                    MinecartRouteSelection=function() return selection end,
                    MinecartRouteMarkerProjection=function() return projection end,
                },
                ['dwarfui/minecart_stop_actions']=stop_actions,
            },
        })
    local extra_stop_actions = state.extra_stop_actions and
        state.extra_stop_actions(stop_actions) or false
    local instance = module.MinecartRouteMarkersOverlay{
        extra_stop_actions=extra_stop_actions,
    }
    instance.bounds_provider = function()
        state.bounds_reads = (state.bounds_reads or 0) + 1
        return state.bounds or {x1=4, y1=4, x2=59, y2=74}
    end
    return instance, selection, stop_actions
end

---Lays out a fullscreen overlay so pooled buttons have real hit regions.
---@param overlay table
local function layout_overlay(overlay)
    local parent = widget_harness.rect(0, 0, 100, 30)
    overlay:preUpdateLayout(parent)
    overlay:updateLayout(parent)
end

---Creates a painter double that records screen-space label and indicator text.
---@return table
local function painter()
    local dc = {strings={}, chars={}}
    function dc:seek(x, y) self.x, self.y = x, y return self end
    function dc:string(text, pen)
        table.insert(self.strings, {x=self.x, y=self.y, text=text, pen=pen})
        return self
    end
    function dc:char(char, pen)
        table.insert(self.chars, {x=self.x, y=self.y, char=char, pen=pen})
        return self
    end
    return dc
end

describe('DwarfUI minecart route markers overlay', function()
    it('registers a fullscreen Hauling overlay and passes native input through',
            function()
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=6, mouse_y=11, markers={},
            map_calls={}, reveals={}, viewport={},
            hauling={routes={[0]={id=8}}, view_routes={[0]={id=8}}},
        }
        local overlay, selection = load_overlay(state)

        assert.is_true(overlay.fullscreen)
        assert.equals('dwarfmode/Hauling', overlay.viewscreens)
        assert.is_false(overlay:onInput({_MOUSE_L=true}))
        assert.equals(8, selection.selected_route_id)
        assert.same({'dwarfmode/Hauling'}, selection.input.focus)
    end)

    it('renders map markers and labels from the current selected route only',
            function()
        local marker = {
            world_pos={x=4, y=7, z=3},
            marker_pen={ch=9, fg='green', keep_lower=true},
            screen_pos={x=5, y=7, z=0}, marker_glyph=string.char(9),
            label='Depot', label_x=5, label_y=9,
        }
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=0, mouse_y=0,
            markers={marker}, map_calls={}, reveals={}, viewport={},
            hauling={routes={[0]={id=8}}, view_routes={[0]={id=8}}},
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = 8
        local dc = painter()

        overlay:render(dc)

        assert.equals(1, #state.map_calls)
        assert.same({x1=4, x2=4, y1=7, y2=7},
            state.map_calls[1].bounds)
        assert.same(marker.marker_pen,
            state.map_calls[1].callback({x=4, y=7, z=9}))
        assert.is_true(marker.marker_pen.keep_lower)
        assert.same({x=5, y=9, text='Depot', pen='green'}, dc.strings[2])
        assert.same({x=5, y=11, text=string.char(16), pen='yellow'},
            dc.strings[1])
        assert.equals(1, state.bounds_reads)

        overlay:render(dc)
        assert.equals(1, state.bounds_reads)
    end)

    it('clears selection when the Hauling screen closes or the overlay disables',
            function()
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=0, mouse_y=0, markers={},
            map_calls={}, reveals={}, viewport={},
            hauling={routes={[0]={id=8}}, view_routes={[0]={id=8}}},
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = 8
        state.focus = {'dwarfmode/Default'}

        overlay:overlay_onupdate()
        assert.is_nil(selection.selected_route_id)
        selection.selected_route_id = 8
        overlay.overlay_ondisable()
        assert.is_nil(selection.selected_route_id)
    end)

    it('renders the vanilla recenter action beside every visible stop row',
            function()
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=0, mouse_y=0,
            markers={}, map_calls={}, reveals={}, viewport={},
            bounds={x1=4, y1=4, x2=59, y2=15},
            hauling={
                routes={[0]={id=8}},
                view_routes={
                    [0]={id=8},
                    [1]={id=8},
                },
                view_stops={
                    [0]={id=80, pos={x=10, y=20, z=3}},
                    [1]={id=81, pos={x=11, y=21, z=3}},
                },
                scroll_position=0,
            },
        }
        local overlay = load_overlay(state)
        layout_overlay(overlay)
        overlay:render(painter())

        local action = overlay.stop_actions[1]
        assert.equals('recenter', action.id)
        assert.same({3, 3}, {action.width, action.height})
        assert.same({page='INTERFACE_BITS', x=32, y=0}, action.asset)
        assert.equals(string.char(26) .. 'X ', action.chars[2])
        assert.same({3, 4, 0}, {
            action.pens[2][1].fg,
            action.pens[2][2].fg,
            action.pens[2][3].fg,
        })
        for _, row in ipairs(action.pens) do
            for _, pen in ipairs(row) do
                assert.is_true(pen.keep_lower,
                    'recenter asset cells must preserve the native panel')
            end
        end
        assert.equals(string.char(26) .. ' X', action.tooltip)

        local buttons = overlay.stop_action_pool:get_buttons('recenter')
        assert.equals(2, #buttons)
        assert.same({60, 10, 3, 3}, {
            buttons[1].frame.l,
            buttons[1].frame.t,
            buttons[1].frame.w,
            buttons[1].frame.h,
        })
        assert.same({60, 13}, {
            buttons[2].frame.l,
            buttons[2].frame.t,
        })
    end)

    it('consumes a zoom click and reveals a copied current stop position',
            function()
        local stop_pos = {x=17, y=29, z=4}
        local route = {id=8}
        local stop = {id=80, pos=stop_pos}
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=61, mouse_y=11,
            markers={}, map_calls={}, reveals={}, viewport={},
            bounds={x1=4, y1=4, x2=59, y2=12},
            hauling={
                routes={[0]=route},
                view_routes={[0]=route},
                view_stops={[0]=stop},
                scroll_position=0,
            },
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = 8
        layout_overlay(overlay)
        local routes = state.hauling.routes
        local scroll_position = state.hauling.scroll_position
        local route_snapshot = {id=route.id}
        local stop_snapshot = {
            id=stop.id,
            pos={x=stop.pos.x, y=stop.pos.y, z=stop.pos.z},
        }

        assert.is_true(overlay:onInput({_MOUSE_L=true}))

        assert.equals(1, #state.reveals)
        assert.same({x=17, y=29, z=4}, state.reveals[1].pos)
        assert.is_not.equal(stop_pos, state.reveals[1].pos)
        assert.is_true(state.reveals[1].center)
        assert.is_true(state.reveals[1].highlight)
        assert.is_nil(selection.input)
        assert.equals(8, selection.selected_route_id)
        assert.is.equal(routes, state.hauling.routes)
        assert.equals(scroll_position, state.hauling.scroll_position)
        assert.same(route_snapshot, route)
        assert.same(stop_snapshot, stop)
        assert.same({'dwarfmode/Hauling'}, state.focus)
    end)

    it('rejects stale row, identity, position, and scroll bindings safely',
            function()
        local route = {id=8}
        local stop = {id=80, pos={x=17, y=29, z=4}}
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=61, mouse_y=11,
            markers={}, map_calls={}, reveals={}, viewport={},
            bounds={x1=4, y1=4, x2=59, y2=12},
            hauling={
                routes={[0]=route},
                view_routes={[0]=route},
                view_stops={[0]=stop},
                scroll_position=0,
            },
        }
        local overlay = load_overlay(state)
        layout_overlay(overlay)
        overlay:ensure_menu_bounds()
        overlay:refresh_stop_actions(state.hauling)
        local button =
            overlay.stop_action_pool:get_buttons('recenter')[1]

        stop.id = 81
        assert.has_no.errors(function() button:activate() end)
        route.id, stop.id = 9, 80
        assert.has_no.errors(function() button:activate() end)
        route.id = 8
        stop.pos = nil
        assert.has_no.errors(function() button:activate() end)
        stop.pos = {x=17, y=29, z=4}
        state.hauling.scroll_position = 1
        assert.has_no.errors(function() button:activate() end)
        state.hauling.view_stops[0] = false
        state.hauling.scroll_position = 0
        assert.has_no.errors(function() button:activate() end)

        assert.equals(0, #state.reveals)
    end)

    it('passes ordinary native row clicks through after button dispatch',
            function()
        local route = {id=8}
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=6, mouse_y=11,
            markers={}, map_calls={}, reveals={}, viewport={},
            bounds={x1=4, y1=4, x2=59, y2=12},
            hauling={
                routes={[0]=route},
                view_routes={[0]=route},
                view_stops={[0]=false},
                scroll_position=0,
            },
        }
        local overlay, selection = load_overlay(state)
        layout_overlay(overlay)

        assert.is_false(overlay:onInput({_MOUSE_L=true}))
        assert.equals(8, selection.selected_route_id)
        assert.is_not_nil(selection.input)
        assert.equals(0, #state.reveals)
    end)

    it('adds a second action without changing stop-row layout code',
            function()
        local synthetic_activations = {}
        local route = {id=8}
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=63, mouse_y=11,
            markers={}, map_calls={}, reveals={}, viewport={},
            bounds={x1=4, y1=4, x2=59, y2=12},
            hauling={
                routes={[0]=route},
                view_routes={[0]=route},
                view_stops={
                    [0]={id=80, pos={x=17, y=29, z=4}},
                },
                scroll_position=0,
            },
            extra_stop_actions=function(stop_actions)
                return {
                    stop_actions.MinecartStopActionDefinition{
                        id='synthetic',
                        width=1,
                        height=3,
                        chars={'S', 'S', 'S'},
                        tooltip='S',
                        on_activate=function(descriptor)
                            table.insert(
                                synthetic_activations, descriptor.stop_id)
                        end,
                    },
                }
            end,
        }
        local overlay = load_overlay(state)
        layout_overlay(overlay)
        overlay:render(painter())
        local active = overlay.stop_action_pool:get_active_buttons()

        assert.equals(2, #active)
        assert.same({'recenter', 'synthetic'}, {
            active[1].action_descriptor.action_id,
            active[2].action_descriptor.action_id,
        })
        assert.same({60, 63}, {
            active[1].frame.l,
            active[2].frame.l,
        })
        assert.is_true(overlay:onInput({_MOUSE_L=true}))
        assert.same({80}, synthetic_activations)
        assert.equals(0, #state.reveals)
    end)

    it('renders stop action buttons above map markers', function()
        local route = {id=8}
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=0, mouse_y=0,
            markers={{
                world_pos={x=4, y=7, z=3},
                marker_pen={ch=9, fg='green', keep_lower=true},
                label='Stop', label_x=4, label_y=9,
            }},
            map_calls={}, render_events={}, reveals={}, viewport={},
            bounds={x1=4, y1=4, x2=59, y2=12},
            hauling={
                routes={[0]=route},
                view_routes={[0]=route},
                view_stops={
                    [0]={id=80, pos={x=17, y=29, z=4}},
                },
                scroll_position=0,
            },
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = 8
        layout_overlay(overlay)
        overlay:render(painter())
        local button =
            overlay.stop_action_pool:get_buttons('recenter')[1]
        button.onRenderBody = function()
            table.insert(state.render_events, 'button')
        end
        state.render_events = {}

        overlay:render(painter())

        assert.same({'map', 'button'}, state.render_events)
    end)
end)
