local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

---Loads the route-marker overlay with isolated DFHack collaborators.
---@param state table
---@return table
---@return table
local function load_overlay(state)
    local widgets = widget_harness.widgets()
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
        find_route_header_y=function(_, _, route_id)
            return route_id and 10 or nil
        end,
    }
    local projection = {
        project=function() return state.markers end,
    }
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui-minecart-route-markers.lua', {
            globals={
                defclass=test_defclass,
                COLOR_YELLOW='yellow',
                df={global={gps={dimy=25}, plotinfo={hauling=state.hauling}}},
                dfhack={
                    gui={getCurFocus=function() return state.focus end},
                    screen={getMousePos=function() return state.mouse_x,
                        state.mouse_y end},
                },
            },
            require_modules={
                ['plugins.overlay']={OverlayWidget=OverlayWidget},
                ['gui.dwarfmode']={
                    Viewport={get=function() return state.viewport end},
                    renderMapOverlay=function(callback, bounds)
                        table.insert(state.map_calls, {callback=callback,
                            bounds=bounds})
                    end,
                },
            },
            reqscript={
                ['dwarfui/minecart_route']={
                    MinecartRouteMenuLayout=function() return layout end,
                    MinecartRouteSelection=function() return selection end,
                    MinecartRouteMarkerProjection=function() return projection end,
                },
            },
        })
    return module.MinecartRouteMarkersOverlay{}, selection
end

---Creates a painter double that records screen-space label and indicator text.
---@return table
local function painter()
    local dc = {strings={}}
    function dc:seek(x, y) self.x, self.y = x, y return self end
    function dc:string(text, pen)
        table.insert(self.strings, {x=self.x, y=self.y, text=text, pen=pen})
        return self
    end
    return dc
end

describe('DwarfUI minecart route markers overlay', function()
    it('registers a fullscreen Hauling overlay and passes native input through',
            function()
        local state = {
            focus='dwarfmode/Hauling', mouse_x=6, mouse_y=11, markers={},
            map_calls={}, viewport={},
            hauling={routes={[0]={id=8}}, view_routes={[0]={id=8}}},
        }
        local overlay, selection = load_overlay(state)

        assert.is_true(overlay.fullscreen)
        assert.equals('dwarfmode/Hauling', overlay.viewscreens)
        assert.is_false(overlay:onInput({_MOUSE_L=true}))
        assert.equals(8, selection.selected_route_id)
        assert.same('dwarfmode/Hauling', selection.input.focus)
    end)

    it('renders map markers and labels from the current selected route only',
            function()
        local marker = {
            world_pos={x=4, y=7, z=3}, marker_pen={fg='green'},
            marker_glyph=string.char(15), label='Depot', label_x=5, label_y=7,
        }
        local state = {
            focus='dwarfmode/Hauling', mouse_x=0, mouse_y=0,
            markers={marker}, map_calls={}, viewport={},
            hauling={routes={[0]={id=8}}, view_routes={[0]={id=8}}},
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = 8
        local dc = painter()

        overlay:render(dc)

        assert.equals(1, #state.map_calls)
        assert.same({x1=4, x2=4, y1=7, y2=7}, state.map_calls[1].bounds)
        assert.equals('green', state.map_calls[1].callback({x=4, y=7, z=9}))
        assert.same({x=5, y=7, text='Depot', pen='green'}, dc.strings[2])
        assert.same({x=0, y=11, text=string.char(16), pen='yellow'},
            dc.strings[1])
    end)

    it('clears selection when the Hauling screen closes or the overlay disables',
            function()
        local state = {
            focus='dwarfmode/Hauling', mouse_x=0, mouse_y=0, markers={},
            map_calls={}, viewport={},
            hauling={routes={[0]={id=8}}, view_routes={[0]={id=8}}},
        }
        local overlay, selection = load_overlay(state)
        selection.selected_route_id = 8
        state.focus = 'dwarfmode/Default'

        overlay:overlay_onupdate()
        assert.is_nil(selection.selected_route_id)
        selection.selected_route_id = 8
        overlay.overlay_ondisable()
        assert.is_nil(selection.selected_route_id)
    end)
end)
