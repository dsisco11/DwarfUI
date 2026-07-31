local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local MarkerKind = {
    SAME_Z=1,
    ABOVE=2,
    BELOW=3,
}
local PointerPolicy = {PASS=2}

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
        select_route=function(self, route)
            if not route or type(route.id) ~= 'number' then return false end
            self.selected_route_id = route.id
            return true
        end,
        resolve_selected_route=function(self, routes)
            if not routes or self.selected_route_id == nil then return nil end
            local index = 0
            while routes[index] do
                if routes[index].id == self.selected_route_id then
                    return routes[index]
                end
                index = index + 1
            end
            self.selected_route_id = nil
            return nil
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
    local tooltip = {
        register=function(widget)
            state.tooltip_registrations = state.tooltip_registrations or {}
            table.insert(state.tooltip_registrations, widget)
        end,
        register_map_tile=function(options)
            state.map_tooltip_sequence =
                (state.map_tooltip_sequence or 0) + 1
            local handle = {sequence=state.map_tooltip_sequence}
            state.map_tooltips = state.map_tooltips or {}
            state.map_tooltips[handle] = {
                owner=options.owner,
                pos={
                    x=options.pos.x,
                    y=options.pos.y,
                    z=options.pos.z,
                },
                tooltip=options.tooltip,
            }
            return handle
        end,
        update_map_tile=function(handle, update)
            local record = state.map_tooltips and
                state.map_tooltips[handle] or nil
            if not record then return false end
            record.pos = {
                x=update.pos.x,
                y=update.pos.y,
                z=update.pos.z,
            }
            record.tooltip = update.tooltip
            return true
        end,
        unregister_map_tile=function(handle)
            local record = state.map_tooltips and
                state.map_tooltips[handle] or nil
            if not record then return false end
            state.map_tooltips[handle] = nil
            state.map_tooltip_removals =
                (state.map_tooltip_removals or 0) + 1
            return true
        end,
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
    local _, hover_action_rail = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/widgets/hover_action_rail.lua', {
            globals={
                DEFAULT_NIL=default_nil,
                defclass=widget_harness.defclass,
                dfhack={pen={parse=function(value) return value end}},
            },
            require_modules={
                gui={paint_frame=function() end},
                ['gui.widgets']=widgets,
            },
            reqscript={
                ['dwarfui/class']=select(2, module_loader.load(repo_root,
                    'src/scripts_modinstalled/dwarfui/class.lua')),
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
                        getDFViewscreen=function()
                            return state.native_screen or {}
                        end,
                        getFocusStrings=function()
                            return state.focus
                        end,
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
                    MinecartRouteMarkerKind=MarkerKind,
                },
                ['dwarfui/widgets/asset_button']=asset_button,
                ['dwarfui/widgets/hover_action_rail']=hover_action_rail,
                ['dwarfui/tooltip/api']=tooltip,
                ['dwarfui/pointer']={PointerPolicy=PointerPolicy},
            },
        })
    local instance = module.MinecartRouteMarkersOverlay{}
    instance.hauling_provider = function() return state.hauling end
    instance.bounds_provider = function()
        state.bounds_reads = (state.bounds_reads or 0) + 1
        return state.bounds or {x1=4, y1=4, x2=59, y2=74}
    end
    return instance, selection, hover_action_rail
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
    local dc = {strings={}, chars={}, fills={}}
    function dc:seek(x, y) self.x, self.y = x, y return self end
    function dc:string(text, pen)
        table.insert(self.strings, {x=self.x, y=self.y, text=text, pen=pen})
        return self
    end
    function dc:char(char, pen)
        table.insert(self.chars, {x=self.x, y=self.y, char=char, pen=pen})
        return self
    end
    function dc:fill(rect, pen)
        table.insert(self.fills, {rect=rect, pen=pen})
        return self
    end
    return dc
end

---Creates a complete marker descriptor for overlay integration tests.
---@param stop_id integer
---@param marker_kind integer
---@param name string
---@param pos {x: integer, y: integer, z: integer}
---@return table
local function marker(stop_id, marker_kind, name, pos)
    return {
        stop_id=stop_id,
        marker_kind=marker_kind,
        world_pos={x=pos.x, y=pos.y, z=pos.z},
        marker_pen={ch=9, fg='green', keep_lower=true},
        label=name ~= '' and name or '(unnamed)',
        label_x=pos.x + 20,
        label_y=pos.y + 20,
    }
end

---Counts active map-tooltip records in a test state.
---@param state table
---@return integer
local function map_tooltip_count(state)
    local count = 0
    for _ in pairs(state.map_tooltips or {}) do count = count + 1 end
    return count
end

describe('DwarfUI minecart route markers overlay', function()
    it('declares a fullscreen Hauling overlay and returns false for ordinary input',
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

    it('registers only same-z markers at their exact world tiles', function()
        local route = {id=8}
        local same_z = marker(80, MarkerKind.SAME_Z, 'Depot',
            {x=17, y=29, z=4})
        local above = marker(81, MarkerKind.ABOVE, 'Upper',
            {x=18, y=29, z=5})
        local below = marker(82, MarkerKind.BELOW, 'Lower',
            {x=19, y=29, z=3})
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=0, mouse_y=0,
            markers={same_z, above, below},
            map_calls={}, reveals={}, viewport={},
            hauling={routes={[0]=route}, view_routes={[0]=route}},
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = route.id

        overlay:render(painter())

        assert.equals(1, map_tooltip_count(state))
        local handle = overlay.map_tooltip_handles[80]
        assert.is_not_nil(handle)
        assert.same({x=17, y=29, z=4},
            state.map_tooltips[handle].pos)
        assert.equals('Depot', state.map_tooltips[handle].tooltip)
        assert.is_equal(overlay, state.map_tooltips[handle].owner)
        assert.is_nil(overlay.map_tooltip_handles[81])
        assert.is_nil(overlay.map_tooltip_handles[82])
        assert.equals(3, #state.map_calls,
            'off-z descriptors must keep rendering as markers')
        assert.is_nil(overlay.map_tooltip_handles[same_z.label_x],
            'the adjacent label cell must not become a map target')
    end)

    it('refreshes names, positions, membership, and duplicate order', function()
        local route = {id=8}
        local first = marker(80, MarkerKind.SAME_Z, 'First',
            {x=17, y=29, z=4})
        local second = marker(81, MarkerKind.SAME_Z, '',
            {x=17, y=29, z=4})
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=0, mouse_y=0,
            markers={first, second},
            map_calls={}, reveals={}, viewport={},
            hauling={routes={[0]=route}, view_routes={[0]=route}},
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = route.id
        overlay:render(painter())
        local first_handle = overlay.map_tooltip_handles[80]
        local second_handle = overlay.map_tooltip_handles[81]

        assert.equals('(unnamed)',
            state.map_tooltips[second_handle].tooltip)
        first.world_pos = {x=18, y=30, z=4}
        first.label = 'Renamed'
        overlay:render(painter())
        assert.is_equal(first_handle, overlay.map_tooltip_handles[80])
        assert.same({x=18, y=30, z=4},
            state.map_tooltips[first_handle].pos)
        assert.equals('Renamed', state.map_tooltips[first_handle].tooltip)

        state.markers = {second, first}
        overlay:render(painter())
        assert.is_not.equal(first_handle, overlay.map_tooltip_handles[80])
        assert.is_not.equal(second_handle, overlay.map_tooltip_handles[81])
        assert.same({81, 80}, overlay.map_tooltip_order)
        assert.equals(2, map_tooltip_count(state))

        table.remove(state.markers, 1)
        overlay:render(painter())
        assert.same({80}, overlay.map_tooltip_order)
        assert.equals(1, map_tooltip_count(state))

        table.insert(state.markers, marker(82, MarkerKind.SAME_Z, 'Added',
            {x=21, y=31, z=4}))
        overlay:render(painter())
        assert.same({80, 82}, overlay.map_tooltip_order)
        assert.equals(2, map_tooltip_count(state))

        local stale_handle = overlay.map_tooltip_handles[80]
        state.map_tooltips = {}
        overlay:render(painter())
        assert.is_not.equal(stale_handle, overlay.map_tooltip_handles[80])
        assert.equals(2, map_tooltip_count(state),
            'lost registry handles must be rebuilt after module reload')
    end)

    it('replaces route targets and removes targets after z or context changes',
            function()
        local first_route = {id=8}
        local second_route = {id=9}
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=0, mouse_y=0,
            markers={marker(80, MarkerKind.SAME_Z, 'First route',
                {x=17, y=29, z=4})},
            map_calls={}, reveals={}, viewport={},
            hauling={
                routes={[0]=first_route},
                view_routes={[0]=first_route},
            },
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = first_route.id
        overlay:render(painter())
        local old_handle = overlay.map_tooltip_handles[80]

        state.hauling.routes[0] = second_route
        state.hauling.view_routes[0] = second_route
        selection.selected_route_id = second_route.id
        state.markers = {marker(90, MarkerKind.SAME_Z, 'Second route',
            {x=40, y=41, z=4})}
        overlay:render(painter())
        assert.is_nil(state.map_tooltips[old_handle])
        assert.is_nil(overlay.map_tooltip_handles[80])
        assert.equals('Second route',
            state.map_tooltips[overlay.map_tooltip_handles[90]].tooltip)

        local rendered_before_z_change = #state.map_calls
        state.markers[1].marker_kind = MarkerKind.ABOVE
        overlay:render(painter())
        assert.equals(0, map_tooltip_count(state))
        assert.equals(rendered_before_z_change + 1, #state.map_calls,
            'the off-z marker must remain rendered')

        state.markers = {marker(90, MarkerKind.SAME_Z, 'Second route',
            {x=40, y=41, z=5})}
        overlay:render(painter())
        assert.equals(1, map_tooltip_count(state))
        state.hauling.routes = {}
        overlay:overlay_onupdate()
        assert.is_nil(selection.selected_route_id)
        assert.equals(0, map_tooltip_count(state))
    end)

    it('clears selection when the Hauling screen closes or the overlay disables',
            function()
        local marker_descriptor = marker(
            80, MarkerKind.SAME_Z, 'Depot', {x=17, y=29, z=4})
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=6, mouse_y=11,
            markers={marker_descriptor},
            map_calls={}, reveals={}, viewport={},
            bounds={x1=4, y1=4, x2=59, y2=12},
            hauling={
                routes={[0]={id=8}}, view_routes={[0]={id=8}},
                view_stops={[0]={id=80, pos={x=17, y=29, z=4}}},
            },
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = 8
        layout_overlay(overlay)
        overlay:render(painter())
        assert.is_not_nil(overlay.stop_rail:get_target())
        assert.equals(1, map_tooltip_count(state))
        assert.same({overlay.stop_rail.action_widgets[1]},
            state.tooltip_registrations)
        state.focus = {'dwarfmode/Default'}

        overlay:overlay_onupdate()
        assert.is_nil(selection.selected_route_id)
        assert.is_nil(overlay.stop_rail:get_target())
        assert.equals(0, map_tooltip_count(state))
        assert.same({overlay.stop_rail.action_widgets[1]},
            state.tooltip_registrations)
        selection.selected_route_id = 8
        state.focus = {'dwarfmode/Hauling'}
        state.mouse_x = 6
        overlay:render(painter())
        assert.equals(1, map_tooltip_count(state))

        local hauling = state.hauling
        state.hauling = nil
        overlay:overlay_onupdate()
        assert.is_nil(selection.selected_route_id)
        assert.equals(0, map_tooltip_count(state))

        state.hauling = hauling
        selection.selected_route_id = 8
        overlay:render(painter())
        assert.equals(1, map_tooltip_count(state))
        overlay.overlay_ondisable()
        assert.is_nil(selection.selected_route_id)
        assert.is_nil(overlay.stop_rail:get_target())
        assert.equals(0, map_tooltip_count(state))
        assert.same({overlay.stop_rail.action_widgets[1]},
            state.tooltip_registrations)
    end)

    it('shows one left-side hover rail only for a current stop entry',
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

        assert.is_false(overlay.stop_rail.surface.visible)
        state.mouse_x, state.mouse_y = 6, 11
        overlay:render(painter())
        local action = overlay.stop_rail.action_widgets[1]
        assert.equals('recenter', overlay.stop_rail.actions[1].id)
        assert.same({3, 3}, {action.frame.w, action.frame.h})
        assert.same({page='INTERFACE_BITS', x=32, y=0}, action.asset)
        assert.equals(string.char(26) .. 'X ', action.chars[2])
        assert.same({3, 4, 0}, {
            action.pens[2][1].fg, action.pens[2][2].fg,
            action.pens[2][3].fg,
        })
        for _, row in ipairs(action.pens) do
            for _, pen in ipairs(row) do
                assert.is_true(pen.keep_lower,
                    'recenter asset cells must preserve the native panel')
            end
        end
        assert.equals('Zoom to this stop', action.tooltip)
        assert.same({action}, state.tooltip_registrations)
        state.mouse_x, state.mouse_y = 2, 11
        overlay:render(painter())
        assert.same({action}, state.tooltip_registrations)
        assert.equals(PointerPolicy.PASS, overlay.stop_rail.pointer_policy)
        assert.is_true(overlay.stop_rail.surface.visible)
        assert.equals('left', overlay.stop_rail.placement)
        assert.same({fg=0, bg=0, keep_lower=true},
            overlay.stop_rail.surface.frame_background)
        assert.same({0, 0, 3, 3}, {action.frame.l, action.frame.t,
            action.frame.w, action.frame.h})
        assert.same({1, 10, 3, 3}, {overlay.stop_rail.surface.frame.l,
            overlay.stop_rail.surface.frame.t, overlay.stop_rail.surface.frame.w,
            overlay.stop_rail.surface.frame.h})
        assert.equals(3, overlay.stop_rail.rail_bounds.x2)
        assert.equals(4, overlay.stop_rail.active_target.anchor.x1)
        assert.equals('8:80', overlay:target_at_stop(4, 11).key)
        assert.equals('8:80', overlay:target_at_stop(58, 11).key)
        state.mouse_x, state.mouse_y = 4, 9
        overlay:render(painter())
        assert.is_false(overlay.stop_rail.surface.visible,
            'route headers must not create a stop rail')
        assert.is_nil(overlay:target_at_stop(59, 11),
            'the native scrollbar column must not create a stop target')
    end)

    it('consumes a zoom click and reveals a copied current stop position',
            function()
        local stop_pos = {x=17, y=29, z=4}
        local route = {id=8}
        local stop = {id=80, pos=stop_pos}
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=6, mouse_y=11,
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
        selection.selected_route_id = nil
        layout_overlay(overlay)
        local routes = state.hauling.routes
        local scroll_position = state.hauling.scroll_position
        local route_snapshot = {id=route.id}
        local stop_snapshot = {
            id=stop.id,
            pos={x=stop.pos.x, y=stop.pos.y, z=stop.pos.z},
        }

        overlay:render(painter())
        state.mouse_x = 2
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
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = 8
        layout_overlay(overlay)
        overlay:render(painter())
        local button = overlay.stop_rail.action_widgets[1]
        selection.selected_route_id = 77

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
        assert.equals(77, selection.selected_route_id,
            'stale zoom actions must not change route selection')
    end)

    it('returns false for ordinary row clicks after button dispatch',
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

    it('rejects incomplete or invalid native list state without raising',
            function()
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=6, mouse_y=11,
            markers={}, map_calls={}, reveals={}, viewport={},
            bounds={x1=4, y1=4, x2=59, y2=12},
            hauling={view_routes={[0]={id=8}}},
        }
        local overlay = load_overlay(state)
        layout_overlay(overlay)
        overlay:ensure_menu_bounds()
        assert.has_no.errors(function() overlay:render(painter()) end)
        assert.is_nil(overlay:target_at_stop(6, 11))

        state.hauling.view_stops = {[0]={id=80, pos={x=17, y=29, z=4}}}
        state.hauling.scroll_position = 'not a row'
        assert.has_no.errors(function() overlay:render(painter()) end)
        assert.is_nil(overlay:target_at_stop(6, 11))
    end)

    it('consumes rail wheel input and refreshes after reported list scrolling',
            function()
        local route = {id=8}
        local state = {
            focus={'dwarfmode/Hauling'}, mouse_x=6, mouse_y=11,
            markers={}, map_calls={}, reveals={}, viewport={},
            bounds={x1=4, y1=4, x2=59, y2=15},
            hauling={
                routes={[0]=route, [1]=route},
                view_routes={[0]=route, [1]=route},
                view_stops={
                    [0]={id=80, pos={x=17, y=29, z=4}},
                    [1]={id=81, pos={x=18, y=30, z=4}},
                },
                scroll_position=0,
            },
        }
        local overlay = load_overlay(state)
        layout_overlay(overlay)
        overlay:render(painter())
        assert.equals('8:80', overlay.stop_rail:get_target().key)

        state.mouse_x = 2
        assert.is_true(overlay:onInput({CONTEXT_SCROLL_DOWN=true}),
            'the rail must own wheel input over its surface')
        assert.equals(0, state.hauling.scroll_position)

        state.mouse_x = 6
        assert.is_false(overlay:onInput({CONTEXT_SCROLL_DOWN=true}),
            'wheel input over the native list must pass through')
        state.hauling.scroll_position = 1
        overlay:render(painter())
        assert.equals('8:81', overlay.stop_rail:get_target().key,
            'the rail must bind the stop now under the pointer after scrolling')
    end)

    it('draws the hover rail after selected route markers', function()
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
        state.mouse_x, state.mouse_y = 6, 11
        overlay:render(painter())
        local button = overlay.stop_rail.action_widgets[1]
        button.onRenderBody = function()
            table.insert(state.render_events, 'button')
        end
        state.render_events = {}

        overlay:render(painter())

        assert.same({'map', 'button'}, state.render_events)
    end)
end)
