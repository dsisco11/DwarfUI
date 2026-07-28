-- Focused native coverage for the minecart stop zoom tooltip.

local utils = require('utils')

local REGISTERED_WIDGET =
    'dwarfui-minecart-route-markers.minecart_route_markers'

---Returns one fully visible native minecart stop row.
---@param hauling df.hauling_handlerst
---@param layout dwarfui.MinecartRouteMenuLayout
---@return {x: integer, y: integer}
local function find_visible_stop(hauling, layout)
    local first = hauling.scroll_position or 0
    local visible_count = math.floor(
        (layout.bounds.y2 - layout.first_row_top + 1) /
            layout.row_height)
    for visible=0,visible_count - 1 do
        local index = first + visible
        local route = hauling.view_routes[index]
        local stop = hauling.view_stops[index]
        if route and stop and stop.pos then
            return {
                x=layout.bounds.x1 + 2,
                y=layout.first_row_top +
                    visible * layout.row_height + 1,
            }
        end
    end
    error('prepared save requires one fully visible minecart stop')
end

describe('native minecart zoom tooltip', function()
    it('uses the singleton tooltip service for the rendered stop action',
            function()
        local native_subject
        local overlay
        local initially_open
        local initial_scroll
        local ok, failure = xpcall(function()
            native_subject = ds.mountNativeScreen()
            initially_open = utils.linear_index(
                native_subject:getFocusList(), 'dwarfmode/Hauling') ~= nil
            if initially_open then
                ds.input('LEAVESCREEN')
                ds.await('pre-existing Hauling menu closes', function()
                    return utils.linear_index(native_subject:getFocusList(),
                        'dwarfmode/Default') ~= nil
                end)
            end

            ds.input('D_HAULING')
            ds.await('native Hauling menu opens', function()
                return utils.linear_index(native_subject:getFocusList(),
                    'dwarfmode/Hauling') ~= nil
            end)

            local hauling = assert(df.global.plotinfo.hauling,
                'native Hauling state is unavailable')
            initial_scroll = hauling.scroll_position
            local source = {
                source='overlay',
                overlay=REGISTERED_WIDGET,
            }
            local rail_subject
            local surface_subject
            local zoom_subject
            ds.await('registered minecart controls observe Hauling',
                function()
                    local rail_ok, selected_rail = pcall(
                        ds.get, 'stop_action_rail', source)
                    local surface_ok, selected_surface = pcall(
                        ds.get, 'stop_action_rail/surface', source)
                    local zoom_ok, selected_zoom = pcall(
                        ds.get, 'stop_action_rail/surface/recenter', source)
                    if not rail_ok or not surface_ok or not zoom_ok then
                        return false
                    end
                    local selected_overlay =
                        selected_rail:raw().parent_view
                    if not selected_overlay or
                            not selected_overlay.layout.bounds then
                        return false
                    end
                    rail_subject = selected_rail
                    surface_subject = selected_surface
                    zoom_subject = selected_zoom
                    return true
                end)

            local rail = rail_subject:raw()
            overlay = assert(rail.parent_view,
                'selected rail has no production overlay parent')
            local action = zoom_subject:raw()
            local stop = find_visible_stop(hauling, overlay.layout)

            ds.move_pointer(stop.x, stop.y)
            ds.redraw()
            ds.await('stop action rail is visible', function()
                return surface_subject:inspect().visible
            end)

            zoom_subject:move_pointer()
            ds.redraw()
            ds.await('singleton presents the zoom action tooltip',
                function()
                    local state = ds.tooltip_state()
                    return state.target == action and
                        state.screen and state.screen.renderer.visible and
                        state.screen.renderer.tooltip_text ==
                            'Zoom to this stop'
                end)

            local state = ds.tooltip_state()
            assert.equals(1, state.renderer_count)
            assert.is_equal(action, state.target)
            assert.equals('Zoom to this stop',
                state.screen.renderer.tooltip_text)
        end, debug.traceback)

        if overlay then overlay:clear_overlay_state() end
        if native_subject and initial_scroll ~= nil and
                df.global.plotinfo.hauling then
            df.global.plotinfo.hauling.scroll_position = initial_scroll
        end
        local is_open = native_subject and utils.linear_index(
            native_subject:getFocusList(), 'dwarfmode/Hauling') ~= nil
        if native_subject and initially_open and not is_open then
            ds.input('D_HAULING')
            ds.await('original Hauling menu reopens', function()
                return utils.linear_index(native_subject:getFocusList(),
                    'dwarfmode/Hauling') ~= nil
            end)
        elseif native_subject and not initially_open and is_open then
            ds.input('LEAVESCREEN')
            ds.await('test Hauling menu closes', function()
                return utils.linear_index(native_subject:getFocusList(),
                    'dwarfmode/Default') ~= nil
            end)
        end
        if native_subject then ds.unmount() end
        assert.is_true(ok, failure)
    end)
end)
