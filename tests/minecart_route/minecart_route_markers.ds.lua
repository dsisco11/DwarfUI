-- Mounted component coverage for the production Minecart Route hover rail.
--
-- The prepared fortress must use Premium graphics and contain a scrollable
-- Hauling route list with route headers and stops at distinct world tiles.
-- This test only observes native route data and restores every UI value it
-- changes.

local gui = require('gui')
local widgets = require('gui.widgets')
local spy = require('luassert.spy')

local REGISTERED_WIDGET =
    'dwarfui-minecart-route-markers.minecart_route_markers'

---@class tests.MinecartNativeInteractionScreen: gui.ZScreen
local MinecartNativeInteractionScreen = defclass(nil, gui.ZScreen)
MinecartNativeInteractionScreen.ATTRS{initial_pause=false}

---Builds the movable pointer subject used to address native screen cells.
function MinecartNativeInteractionScreen:init()
    self:addviews{
        widgets.Panel{
            view_id='minecart_route_pointer_target',
            frame={l=0, t=0, w=1, h=1},
        },
    }
end

---Forwards unconsumed input once to the real native fortress screen.
---@param keys table
---@return boolean
function MinecartNativeInteractionScreen:onInput(keys)
    if self:inputToSubviews(keys) then return true end
    self:sendInputToParent(keys)
    return true
end

---Returns a detached coordinate snapshot.
---@param pos {x: integer, y: integer, z: integer}
---@return {x: integer, y: integer, z: integer}
local function copy_coord(pos)
    return {x=pos.x, y=pos.y, z=pos.z}
end

---Returns whether two coordinates name the same map tile.
---@param left {x: integer, y: integer, z: integer}
---@param right {x: integer, y: integer, z: integer}
---@return boolean
local function same_coord(left, right)
    return left.x == right.x and left.y == right.y and left.z == right.z
end

---Returns the clamped dwarfmode map origin for a centered world position.
---@param pos {x: integer, y: integer, z: integer}
---@return integer
---@return integer
local function expected_center_origin(pos)
    local dims = dfhack.gui.getDwarfmodeViewDims()
    local width = dims.map_x2 - dims.map_x1 + 1
    local height = dims.map_y2 - dims.map_y1 + 1
    local max_x = math.max(0, df.global.world.map.x_count - width)
    local max_y = math.max(0, df.global.world.map.y_count - height)
    return math.max(0, math.min(max_x, pos.x - width // 2)),
        math.max(0, math.min(max_y, pos.y - height // 2))
end

---Returns the independently calculated Premium interface position.
---@param pos {x: integer, y: integer, z: integer}
---@return {x: integer, y: integer, z: integer}
local function expected_premium_ui_position(pos)
    local gps = df.global.gps
    local corner = df.global.world.viewport.corner
    local map_tile_pixels = gps.viewport_zoom_factor // 4
    return {
        x=math.ceil(map_tile_pixels * (pos.x - corner.x) /
            gps.tile_pixel_x),
        y=math.ceil(map_tile_pixels * (pos.y - corner.y) /
            gps.tile_pixel_y),
        z=pos.z - corner.z,
    }
end

---Moves DwarfSpec's standard pointer target to one screen cell.
---@param target widgets.Widget
---@param subject dwarfspec.Subject
---@param x integer
---@param y integer
local function move_pointer(target, subject, x, y)
    target.frame.l, target.frame.t = x, y
    target:updateLayout()
    local actual_x, actual_y = ds.move_pointer(subject)
    assert.equals(x, actual_x, 'DwarfSpec pointer x did not reach the cell')
    assert.equals(y, actual_y, 'DwarfSpec pointer y did not reach the cell')
    ds.redraw(subject)
end

---Returns a fully visible route-header row followed by a visible stop row.
---@param hauling df.hauling_handlerst
---@param layout dwarfui.MinecartRouteMenuLayout
---@return table
---@return table
local function find_visible_header_and_stop(hauling, layout)
    local first = hauling.scroll_position or 0
    local visible_count = math.floor((layout.bounds.y2 - layout.first_row_top +
        1) / layout.row_height)
    for visible=0,visible_count - 1 do
        local header_index = first + visible
        local route = hauling.view_routes[header_index]
        if route and not hauling.view_stops[header_index] then
            for next_visible=visible + 1,visible_count - 1 do
                local stop_index = first + next_visible
                local stop_route = hauling.view_routes[stop_index]
                local stop = hauling.view_stops[stop_index]
                if not stop_route or stop_route.id ~= route.id then break end
                if stop and stop.pos then
                    return {
                        index=header_index,
                        route=route,
                        x=layout.bounds.x1 + 2,
                        y=layout.first_row_top + visible * layout.row_height + 1,
                    }, {
                        index=stop_index,
                        route=route,
                        stop=stop,
                        x1=layout.bounds.x1,
                        x2=layout.bounds.x2 - 1,
                        y1=layout.first_row_top + next_visible * layout.row_height,
                        y2=layout.first_row_top +
                            (next_visible + 1) * layout.row_height - 1,
                    }
                end
            end
        end
    end
    error('prepared save requires a visible route header followed by a visible stop')
end

---Returns another fully visible native stop row.
---@param hauling df.hauling_handlerst
---@param layout dwarfui.MinecartRouteMenuLayout
---@param excluded_index integer
---@return table
local function find_other_visible_stop(hauling, layout, excluded_index)
    local first = hauling.scroll_position or 0
    local visible_count = math.floor((layout.bounds.y2 - layout.first_row_top +
        1) / layout.row_height)
    for visible=0,visible_count - 1 do
        local index = first + visible
        local route, stop = hauling.view_routes[index],
            hauling.view_stops[index]
        if index ~= excluded_index and route and stop and stop.pos then
            return {
                index=index,
                route=route,
                stop=stop,
                x1=layout.bounds.x1,
                x2=layout.bounds.x2 - 1,
                y1=layout.first_row_top + visible * layout.row_height,
                y2=layout.first_row_top +
                    (visible + 1) * layout.row_height - 1,
            }
        end
    end
    error('prepared save requires two simultaneously visible stop rows')
end

---Returns a visible stop under the current pointer after a native list scroll.
---@param hauling df.hauling_handlerst
---@param layout dwarfui.MinecartRouteMenuLayout
---@param x integer
---@param y integer
---@return table|nil
local function visible_stop_at(hauling, layout, x, y)
    local index = (hauling.scroll_position or 0) + math.floor(
        (y - layout.first_row_top) / layout.row_height)
    local route, stop = hauling.view_routes[index], hauling.view_stops[index]
    if not route or not stop or not stop.pos then return nil end
    return {index=index, route=route, stop=stop, x=x, y=y}
end

---Waits for a particular rail target key to become visible.
---@param overlay dwarfui.MinecartRouteMarkersOverlay
---@param key string
---@param description string
local function await_target(overlay, key, description)
    ds.await(description, function()
        local rail = overlay.stop_rail
        local target = rail:get_target()
        return rail.surface.visible and target and target.key == key
    end)
end

---Verifies that a recenter activation centered and highlighted one stop.
---@param pos {x: integer, y: integer, z: integer}
---@param description string
local function assert_centered_and_highlighted(pos, description)
    local expected_x, expected_y = expected_center_origin(pos)
    ds.await(description, function()
        local indicator = df.global.game.main_interface.recenter_indicator_m
        return df.global.window_z == pos.z and
            df.global.window_x == expected_x and
            df.global.window_y == expected_y and same_coord(indicator, pos)
    end)
    assert.same(pos, copy_coord(df.global.game.main_interface.recenter_indicator_m))
end

---Asserts that a rendered selection glyph belongs to one route header.
---@param overlay dwarfui.MinecartRouteMarkersOverlay
---@param hauling df.hauling_handlerst
---@param route_id integer
local function assert_selection_indicator(overlay, hauling, route_id)
    local y = assert(overlay.layout:find_route_header_y(hauling, route_id,
        overlay.focus_provider()), 'selected route header is not visible') + 1
    ds.redraw()
    ds.await('selection indicator renders on the native route header', function()
        local tile = dfhack.screen.readTile(overlay.layout:get_indicator_x(), y)
        local color = tile and tile.fg + (tile.bold and 8 or 0) or nil
        return tile and tile.ch == 16 and color == COLOR_YELLOW
    end)
end

---Asserts that every cell in the Premium recenter asset reached the screen.
---@param action dwarfui.AssetButton
local function assert_recenter_asset(action)
    ds.redraw()
    local body = assert(action.frame_body,
        'production recenter action has no rendered body')
    assert.equals(3, body.width)
    assert.equals(3, body.height)
    for y=0,2 do
        for x=0,2 do
            local expected = assert(dfhack.screen.findGraphicsTile(
                'INTERFACE_BITS', 32 + x, y),
                ('recenter asset cell %d,%d is unavailable'):format(x, y))
            local actual = assert(dfhack.screen.readTile(
                body.x1 + x, body.y1 + y),
                ('rendered recenter cell %d,%d is unavailable'):format(x, y))
            assert.equals(expected, actual.tile,
                ('wrong recenter graphics tile at cell %d,%d'):format(x, y))
        end
    end
end

---Returns the projected marker for one real native stop.
---@param markers dwarfui.MinecartRouteMarkerDescriptor[]
---@param stop df.hauling_stop
---@return dwarfui.MinecartRouteMarkerDescriptor
local function find_stop_marker(markers, stop)
    for _, marker in ipairs(markers) do
        if marker.stop_id == stop.id then return marker end
    end
    error(('selected native stop %s was not projected'):format(stop.id))
end

---Asserts that one marker glyph reached DFHack's real map paint boundary.
---@param marker dwarfui.MinecartRouteMarkerDescriptor
---@param paint_tile_spy luassert.spy
local function assert_rendered_marker(marker, paint_tile_spy)
    ds.redraw()
    local map_pos = require('gui.dwarfmode').Viewport.get():tileToScreen(
        marker.world_pos)
    local observed = {}
    for index=#paint_tile_spy.calls,1,-1 do
        local values = paint_tile_spy.calls[index].vals
        local pen, x, y, map = values[1], values[2], values[3], values[6]
        if pen and pen.ch == marker.marker_glyph:byte() then
            table.insert(observed, ('%s,%s map=%s fg=%s lower=%s'):format(
                tostring(x), tostring(y), tostring(map), tostring(pen.fg),
                tostring(pen.keep_lower)))
        end
        if x == map_pos.x and y == map_pos.y and map == true and
                pen and pen.ch == marker.marker_glyph:byte() and
                pen.fg == marker.marker_pen.fg and pen.keep_lower == true then
            return
        end
    end
    error(('registered overlay did not paint marker %d at map cell %d,%d; ' ..
        'calls=%d matching=%s'):format(marker.marker_glyph:byte(),
            map_pos.x, map_pos.y, #paint_tile_spy.calls,
            table.concat(observed, ';')))
end

---Asserts one rendered marker label and its foreground color.
---@param marker dwarfui.MinecartRouteMarkerDescriptor
local function assert_rendered_marker_label(marker)
    ds.redraw()
    for offset=1,#marker.label do
        local tile = dfhack.screen.readTile(
            marker.label_x + offset - 1, marker.label_y)
        local color = tile and tile.fg + (tile.bold and 8 or 0) or nil
        assert.equals(marker.label:byte(offset), tile and tile.ch,
            ('route label %q mismatch at %d,%d offset %d; color=%s/%s ' ..
                'marker=%d,%d world=%d,%d,%d')
                :format(marker.label, marker.label_x, marker.label_y, offset,
                    tostring(color), tostring(marker.marker_pen.fg),
                    marker.screen_pos.x, marker.screen_pos.y,
                    marker.world_pos.x, marker.world_pos.y,
                    marker.world_pos.z))
        assert.equals(marker.marker_pen.fg, color,
            ('route label %q has wrong color at offset %d'):format(
                marker.label, offset))
    end
end

describe('registered Minecart Route overlay against the native menu', function()
    it('uses registry rendering and mounted native input for route interaction',
            function()
        assert.is_true(dfhack.screen.inGraphicsMode(),
            'prepared save must use Premium graphics')
        local gps = df.global.gps
        local saved = {
            mouse_x=gps.mouse_x, mouse_y=gps.mouse_y,
            precise_mouse_x=gps.precise_mouse_x,
            precise_mouse_y=gps.precise_mouse_y,
            window_x=df.global.window_x, window_y=df.global.window_y,
            window_z=df.global.window_z,
            mouse_focus=df.global.enabler.mouse_focus,
            tracking_on=df.global.enabler.tracking_on,
            indicator=copy_coord(df.global.game.main_interface.recenter_indicator_m),
        }
        local overlay_plugin = require('plugins.overlay')
        local screen, hauling, overlay, mount_root, pointer_target, subject
        local initial_scroll, initial_selection, initially_open
        local paint_tile_spy
        local ok, failure = xpcall(function()
            screen = assert(dfhack.gui.getDFViewscreen(true),
                'prepared save must have a fortress viewscreen')
            initially_open = dfhack.gui.matchFocusString('dwarfmode/Hauling',
                screen)

            -- Mount only a transparent input/redraw screen. The minecart
            -- overlay remains owned and dispatched by DFHack's registry.
            mount_root = ds.mount(MinecartNativeInteractionScreen, {
                backing_viewscreen=screen,
                initial_pause=false,
            }):raw()
            ds.viewport(gps.dimx, gps.dimy)
            subject = ds.get('minecart_route_pointer_target')
            pointer_target = subject:raw()

            -- Establish a known native focus through the same mounted input
            -- path used for every later click and wheel event.
            if initially_open then
                ds.input('LEAVESCREEN')
                ds.await('pre-existing Hauling menu closes', function()
                    return dfhack.gui.matchFocusString('dwarfmode/Default',
                        dfhack.gui.getDFViewscreen(true))
                end)
            end

            dfhack.run_command('dwarfui reload')
            ds.await('registered minecart overlay is discovered', function()
                local entry = overlay_plugin.get_state().db[REGISTERED_WIDGET]
                return entry and entry.widget
            end)
            overlay = assert(overlay_plugin.get_state().db[REGISTERED_WIDGET],
                'registered minecart overlay is unavailable').widget
            assert.equals(reqscript('dwarfui/widgets/hover_action_rail').
                HoverActionRail, getmetatable(overlay.stop_rail),
                'registered overlay did not construct the production rail')
            assert.is_false(overlay.layout:is_supported_focus(
                overlay.focus_provider()),
                'registered overlay became active outside native Hauling focus')
            assert.is_false(overlay.stop_rail.surface.visible,
                'registered rail remained visible outside native Hauling focus')

            ds.input('D_HAULING')
            ds.await('native Hauling menu opens', function()
                return dfhack.gui.matchFocusString('dwarfmode/Hauling',
                    dfhack.gui.getDFViewscreen(true))
            end)
            hauling = assert(df.global.plotinfo.hauling,
                'native Hauling state is unavailable')
            initial_scroll = hauling.scroll_position
            ds.await('registered overlay observes the native Hauling menu',
                function()
                    return overlay.layout.bounds and
                        overlay.layout:is_supported_focus(
                            overlay.focus_provider())
                end)
            -- Overlay rescan finishes asynchronously after `dwarfui reload`.
            -- Reacquire its canonical widget only after the native focus and
            -- cached bounds are stable.
            overlay = assert(overlay_plugin.get_state().db[REGISTERED_WIDGET],
                'registered minecart overlay disappeared after rescan').widget
            assert.is_equal(overlay,
                overlay_plugin.get_state().db[REGISTERED_WIDGET].widget,
                'interaction target is not the canonical registry widget')
            initial_selection = overlay.selection:get_selected_route_id()
            -- Premium keep-lower map glyphs compose over the base map tile,
            -- so readTile() exposes the base graphic. Observe DFHack's final
            -- paint call without replacing or bypassing the real renderer.
            paint_tile_spy = spy.on(dfhack.screen, 'paintTile')
            local header, stop = find_visible_header_and_stop(hauling,
                overlay.layout)
            local other_stop = find_other_visible_stop(hauling, overlay.layout,
                stop.index)
            local target_key = stop.route.id .. ':' .. stop.stop.id

            -- Route headers are never hover targets.
            move_pointer(pointer_target, subject, header.x, header.y)
            assert.is_false(overlay.stop_rail.surface.visible)
            ds.mouseInput(ds.EMouseButton.LEFT)
            ds.await('native route-row click selects its route', function()
                return overlay.selection:get_selected_route_id() ==
                    header.route.id
            end)
            assert_selection_indicator(overlay, hauling, header.route.id)

            -- Number, label, and final native-list content cells resolve the
            -- same three-row stop target.
            for _, y in ipairs({stop.y1, stop.y1 + 1, stop.y2}) do
                for _, x in ipairs({stop.x1, stop.x1 + 2, stop.x2}) do
                    move_pointer(pointer_target, subject, x, y)
                    local overlay_x, overlay_y = overlay:getMousePos()
                    assert.equals(x, overlay_x,
                        'mounted production overlay did not receive DwarfSpec pointer x')
                    assert.equals(y, overlay_y,
                        'mounted production overlay did not receive DwarfSpec pointer y')
                    assert.is_table(overlay:target_at_stop(x, y),
                        'production adapter did not resolve the hovered native stop')
                    local rail_x, rail_y = overlay.stop_rail:getMousePos()
                    assert.equals(x, rail_x,
                        'production rail did not convert the pointer x')
                    assert.equals(y, rail_y,
                        'production rail did not convert the pointer y')
                    assert.is_true(overlay.stop_rail.context_active(),
                        'production rail context is not active for native Hauling')
                    assert.is_table(overlay.stop_rail:resolve_target_at_pointer(),
                        'production rail did not resolve its hovered target')
                    await_target(overlay, target_key,
                        ('visible stop cell %d,%d resolves the production rail')
                            :format(x, y))
                end
            end
            local rail = overlay.stop_rail
            assert.equals(1, #rail.subviews,
                'production rail must own exactly one moving surface')
            assert.is_equal(rail.surface, rail.subviews[1])
            assert.equals(1, #rail.action_widgets)
            assert.equals(1, #rail.visible_actions)
            assert.equals('left', rail.placement)
            assert.is_true(rail.rail_bounds.x2 < overlay.layout.bounds.x1,
                'rail must end immediately before the native panel')
            assert.equals(overlay.layout.bounds.x1 - 1, rail.rail_bounds.x2)
            assert.equals(stop.y1, rail.rail_bounds.y1,
                'rail top is not aligned with its three-row stop')
            assert.equals(stop.y2, rail.rail_bounds.y2,
                'rail bottom is not aligned with its three-row stop')
            assert.is_true(rail.surface.frame_background.keep_lower,
                'rail background must preserve native cells')
            assert.is_false(rail.surface.frame_style)
            local action = rail.action_widgets[1]
            assert.equals(reqscript('dwarfui/widgets/asset_button').AssetButton,
                getmetatable(action),
                'production rail did not construct the production AssetButton')
            assert.equals('recenter', rail.actions[1].id)
            assert.equals(3, action.frame.w)
            assert.equals(3, action.frame.h)
            assert.is_table(rail.rail_bounds,
                'mounted rail did not retain a visible surface after rendering')
            local surface_bounds = {
                x1=rail.rail_bounds.x1, y1=rail.rail_bounds.y1,
                x2=rail.rail_bounds.x2, y2=rail.rail_bounds.y2,
            }
            assert.same({page='INTERFACE_BITS', x=32, y=0}, action.asset,
                'production recenter action uses the wrong graphics asset')
            assert.equals(3, #action.chars)
            assert.equals(3, #action.chars[1])

            -- Crossing directly between real stop rows rebinds the one rail
            -- without replacing its production action-widget instance.
            local original_action = action
            local other_key = other_stop.route.id .. ':' .. other_stop.stop.id
            move_pointer(pointer_target, subject, other_stop.x1 + 2,
                other_stop.y1 + 1)
            await_target(overlay, other_key,
                'direct stop-to-stop movement rebinds the production rail')
            assert.is_equal(original_action, rail.action_widgets[1])
            assert.is_false(same_coord(stop.stop.pos, other_stop.stop.pos),
                'prepared visible stops must occupy distinct world tiles')
            move_pointer(pointer_target, subject, stop.x1 + 2, stop.y1 + 1)
            await_target(overlay, target_key,
                'rail rebinds to the original stop without reconstruction')
            assert.is_equal(original_action, rail.action_widgets[1])
            ds.mouseInput(ds.EMouseButton.LEFT)
            ds.await('native stop-row click selects its route', function()
                return overlay.selection:get_selected_route_id() ==
                    stop.route.id
            end)
            assert_selection_indicator(overlay, hauling, stop.route.id)
            assert_recenter_asset(action)

            -- Cross from the stop to the action surface without losing the
            -- target, then click through the mounted component host.
            assert.is_table(rail:get_target(),
                'rail lost its stop target before pointer transfer')
            move_pointer(pointer_target, subject,
                surface_bounds.x2, surface_bounds.y1 + 1)
            local rail_x, rail_y = rail:getMousePos()
            assert.equals(surface_bounds.x2, rail_x)
            assert.equals(surface_bounds.y1 + 1, rail_y)
            assert.is_true(rail.context_active())
            local retained = assert(rail:get_target())
            local payload = retained.payload
            local fresh = overlay:target_at_stop(payload.bounds.x1,
                payload.bounds.y1)
            assert.is_table(fresh,
                ('production adapter did not re-resolve retained row=%s ' ..
                    'scroll=%s bounds=%s,%s-%s,%s')
                    :format(tostring(payload.row_index),
                        tostring(hauling.scroll_position),
                        tostring(payload.bounds.x1),
                        tostring(payload.bounds.y1),
                        tostring(payload.bounds.x2),
                        tostring(payload.bounds.y2)))
            assert.equals(retained.key, fresh.key)
            assert.same(retained.anchor, fresh.anchor)
            assert.same(payload.bounds, fresh.payload.bounds)
            assert.is_table(rail.validate_target(retained),
                'production validation rejected an identical fresh target')
            await_target(overlay, target_key,
                'pointer transfer from stop to rail retains target')
            local before_route_id, before_stop_id = stop.route.id, stop.stop.id
            local before_pos = copy_coord(stop.stop.pos)
            local before_route_object = hauling.view_routes[stop.index]
            local before_stop_object = hauling.view_stops[stop.index]
            local before_route_rows, before_stop_rows =
                #hauling.view_routes, #hauling.view_stops
            ds.click(subject)
            assert_centered_and_highlighted(before_pos,
                'production rail click centers and highlights the stop')
            assert.equals(before_route_id, overlay.selection:get_selected_route_id())
            local resolved_after_zoom = overlay:resolve_selected_route()
            assert.is_truthy(resolved_after_zoom,
                'zoom-selected route did not resolve against native routes')
            assert.equals(before_route_id, resolved_after_zoom.id)
            assert_selection_indicator(overlay, hauling, before_route_id)
            ds.await('native map viewport applies the zoomed stop origin',
                function()
                    local corner = df.global.world.viewport.corner
                    return corner.x == df.global.window_x and
                        corner.y == df.global.window_y and
                        corner.z == df.global.window_z
                end)
            local marker = find_stop_marker(overlay.projection:project(
                resolved_after_zoom, overlay.viewport_provider()), stop.stop)
            assert.equals('same_z', marker.marker_kind)
            assert.equals(string.char(9), marker.marker_glyph)
            assert.same(expected_premium_ui_position(before_pos),
                marker.screen_pos,
                'marker does not use the Premium world-to-UI transform')
            assert.equals(marker.screen_pos.x, marker.label_x)
            assert.equals(marker.screen_pos.y + 2, marker.label_y)
            assert_rendered_marker(marker, paint_tile_spy)
            assert.is_true(marker.label_x >= overlay.frame_body.x1 and
                marker.label_x + #marker.label - 1 <= overlay.frame_body.x2 and
                marker.label_y >= overlay.frame_body.y1 and
                marker.label_y <= overlay.frame_body.y2,
                ('marker label %d,%d-%d is outside overlay body %d,%d-%d,%d')
                    :format(marker.label_x, marker.label_y,
                        marker.label_x + #marker.label - 1,
                        overlay.frame_body.x1, overlay.frame_body.y1,
                        overlay.frame_body.x2, overlay.frame_body.y2))
            assert_rendered_marker_label(marker)

            -- Pan the real map a few tiles while keeping this stop visible,
            -- then prove the registered overlay follows the native viewport.
            local pan_x = before_pos.x >= 4 and before_pos.x - 4 or
                before_pos.x + 4
            dfhack.gui.revealInDwarfmodeMap(
                {x=pan_x, y=before_pos.y, z=before_pos.z}, true, false)
            ds.await('native viewport applies the marker-follow pan',
                function()
                    local corner = df.global.world.viewport.corner
                    return corner.x == df.global.window_x and
                        corner.y == df.global.window_y and
                        corner.z == df.global.window_z
                end)
            local marker_after_pan = find_stop_marker(
                overlay.projection:project(resolved_after_zoom,
                    overlay.viewport_provider()), stop.stop)
            assert.same(expected_premium_ui_position(before_pos),
                marker_after_pan.screen_pos,
                'panned marker does not use the Premium world-to-UI transform')
            assert.is_false(marker_after_pan.screen_pos.x ==
                    marker.screen_pos.x and marker_after_pan.screen_pos.y ==
                    marker.screen_pos.y,
                'route marker did not follow the changed native viewport')
            assert_rendered_marker(marker_after_pan, paint_tile_spy)
            assert_rendered_marker_label(marker_after_pan)
            assert.equals(before_route_id, hauling.view_routes[stop.index].id)
            assert.equals(before_stop_id, hauling.view_stops[stop.index].id)
            assert.is_equal(before_route_object,
                hauling.view_routes[stop.index])
            assert.is_equal(before_stop_object,
                hauling.view_stops[stop.index])
            assert.equals(before_route_rows, #hauling.view_routes)
            assert.equals(before_stop_rows, #hauling.view_stops)
            assert.equals(initial_scroll, hauling.scroll_position)
            assert.is_true(dfhack.gui.matchFocusString('dwarfmode/Hauling',
                dfhack.gui.getDFViewscreen(true)), 'zoom click closed Hauling')

            -- Wheel input over the rail belongs to the rail and must neither
            -- scroll the list nor change the map z-level.
            local z_before_wheel, scroll_before_wheel = df.global.window_z,
                hauling.scroll_position
            ds.mouseInput(ds.EMouseButton.SCROLL_DOWN)
            assert.equals(z_before_wheel, df.global.window_z)
            assert.equals(scroll_before_wheel, hauling.scroll_position)

            -- Native scrolling occurs only while the actual pointer is over
            -- the native list. Find a newly occupied row and prove a later
            -- rail click targets that current stop, not the old one.
            move_pointer(pointer_target, subject, stop.x1 + 2,
                stop.y1 + 1)
            df.global.enabler.mouse_focus = true
            df.global.enabler.tracking_on = 1
            local stale_target = assert(rail:get_target())
            local moved_stop
            for _=1,16 do
                local before_scroll = hauling.scroll_position
                -- DwarfSpec dispatches the wheel at its current virtual pointer
                -- position and mirrors that position to native mouse input.
                ds.mouseInput(ds.EMouseButton.SCROLL_DOWN)
                ds.redraw()
                if hauling.scroll_position ~= before_scroll then
                    moved_stop = visible_stop_at(hauling, overlay.layout,
                        stop.x1 + 2, stop.y1 + 1)
                    if moved_stop and moved_stop.stop.id ~= before_stop_id then
                        break
                    end
                end
            end
            assert.is_table(moved_stop,
                'prepared save must scroll to a different stop at this row')
            assert.is_false(same_coord(before_pos, moved_stop.stop.pos),
                'scrolled replacement stop must occupy a distinct world tile')
            local moved_key = moved_stop.route.id .. ':' .. moved_stop.stop.id
            await_target(overlay, moved_key,
                'rail rebinds after native list scrolling')
            assert.is_nil(rail.validate_target(stale_target),
                'formerly bound stop remained eligible after native scrolling')
            assert.equals(1, #rail.action_widgets,
                'scrolling must reuse the one action-widget set')
            move_pointer(pointer_target, subject, rail.rail_bounds.x2,
                rail.rail_bounds.y1 + 1)
            ds.click(subject)
            assert_centered_and_highlighted(copy_coord(moved_stop.stop.pos),
                'rebound rail click targets the new native stop')
            assert.equals(moved_stop.route.id,
                overlay.selection:get_selected_route_id())

            ds.input('LEAVESCREEN')
            ds.await('native Hauling menu closes', function()
                return dfhack.gui.matchFocusString('dwarfmode/Default',
                    dfhack.gui.getDFViewscreen(true))
            end)
            ds.redraw()
            ds.await('rail clears after native menu closure', function()
                return overlay.stop_rail:get_target() == nil and
                    not overlay.stop_rail.surface.visible
            end)
            assert.is_false(overlay.layout:is_supported_focus(
                overlay.focus_provider()),
                'registered overlay remained eligible after Hauling closed')
        end, debug.traceback)

        if mount_root then ds.unmount() end
        if hauling then hauling.scroll_position = initial_scroll end
        gps.mouse_x, gps.mouse_y = saved.mouse_x, saved.mouse_y
        gps.precise_mouse_x, gps.precise_mouse_y = saved.precise_mouse_x,
            saved.precise_mouse_y
        df.global.window_x, df.global.window_y, df.global.window_z =
            saved.window_x, saved.window_y, saved.window_z
        local indicator = df.global.game.main_interface.recenter_indicator_m
        indicator.x, indicator.y, indicator.z = saved.indicator.x,
            saved.indicator.y, saved.indicator.z
        df.global.enabler.mouse_focus, df.global.enabler.tracking_on =
            saved.mouse_focus, saved.tracking_on
        if overlay then
            overlay:clear_overlay_state()
            overlay.selection.selected_route_id = initial_selection
        end
        if paint_tile_spy then paint_tile_spy:revert() end
        local current = dfhack.gui.getDFViewscreen(true)
        local is_open = current and dfhack.gui.matchFocusString(
            'dwarfmode/Hauling', current)
        if initially_open and not is_open then
            require('gui').simulateInput(current, 'D_HAULING')
            ds.await('original Hauling menu reopens', function()
                return dfhack.gui.matchFocusString('dwarfmode/Hauling',
                    dfhack.gui.getDFViewscreen(true))
            end)
        elseif not initially_open and is_open then
            require('gui').simulateInput(current, 'LEAVESCREEN')
            ds.await('test Hauling menu closes', function()
                return dfhack.gui.matchFocusString('dwarfmode/Default',
                    dfhack.gui.getDFViewscreen(true))
            end)
        end
        assert.equals(saved.mouse_x, gps.mouse_x)
        assert.equals(saved.mouse_y, gps.mouse_y)
        assert.equals(saved.window_x, df.global.window_x)
        assert.equals(saved.window_y, df.global.window_y)
        assert.equals(saved.window_z, df.global.window_z)
        assert.same(saved.indicator, copy_coord(
            df.global.game.main_interface.recenter_indicator_m))
        assert.is_true(ok, failure)
    end)
end)
