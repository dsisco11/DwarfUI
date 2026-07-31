-- Mounted component coverage for the production Minecart Route hover rail.
--
-- The prepared fortress must use Premium graphics and contain a scrollable
-- Hauling route list with route headers and stops at distinct world tiles.
-- This test only observes native route data and restores every UI value it
-- changes.

local spy = require('luassert.spy')
local utils = require('utils')
local MarkerKind =
    reqscript('dwarfui/minecart_route').MinecartRouteMarkerKind
local MinecartRouteFixture = require('tests.minecart_route.support.route_fixture')

local REGISTERED_WIDGET =
    'dwarfui-minecart-route-markers.minecart_route_markers'

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

---Returns a visible route header for a route other than the excluded route.
---@param hauling df.hauling_handlerst
---@param layout dwarfui.MinecartRouteMenuLayout
---@param excluded_route_id integer
---@return table
local function find_other_visible_header(hauling, layout, excluded_route_id)
    local first = hauling.scroll_position or 0
    local visible_count = math.floor((layout.bounds.y2 - layout.first_row_top +
        1) / layout.row_height)
    for visible=0,visible_count - 1 do
        local index = first + visible
        local route = hauling.view_routes[index]
        if route and route.id ~= excluded_route_id and
                not hauling.view_stops[index] then
            return {
                index=index,
                route=route,
                x=layout.bounds.x1 + 2,
                y=layout.first_row_top + visible * layout.row_height + 1,
            }
        end
    end
    error('prepared save requires two visible route headers')
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

---Captures enough of the screen to include one cached native panel.
---@param name string
---@param bounds {x1: integer, y1: integer, x2: integer, y2: integer}
---@return dwarfspec.ScreenCapture
local function capture_panel(name, bounds)
    return ds.capture_screen(name, {
        max_width=bounds.x2 + 1,
        max_height=bounds.y2 + 1,
    })
end

---Returns one captured zero-based screen cell.
---@param capture dwarfspec.ScreenCapture
---@param x integer
---@param y integer
---@return table|nil
local function captured_cell(capture, x, y)
    local row = capture.cells[y + 1]
    return row and row[x + 1] or nil
end

---Returns the first rendered text cell for one tooltip intent.
---@param intent dwarfui.TooltipIntent
---@return integer
---@return integer
local function tooltip_text_cell(intent)
    local screen_width, screen_height = dfhack.screen.getWindowSize()
    local content_width = math.max(1, math.min(60, screen_width - 2))
    local lines = reqscript('dwarfui/text').wrap_text(
        intent.text, content_width)
    local width = 2
    for _, line in ipairs(lines) do
        width = math.max(width, #line + 2)
    end
    local height = #lines + 2
    local left = math.max(0,
        math.min(intent.anchor_x + 2, screen_width - width))
    local top = math.max(0,
        math.min(intent.anchor_y + 1, screen_height - height))
    return left + 1, top + 1
end

---Asserts that one tooltip's current native text reached the final screen.
---@param intent dwarfui.TooltipIntent
---@param expected string
local function assert_rendered_tooltip_text(intent, expected)
    local x, y = tooltip_text_cell(intent)
    ds.await('map tooltip reaches the final native render seam', function()
        local state = ds.tooltip_state()
        return state.presenter.last_rendered_revision and
            state.presenter.last_rendered_revision >= intent.revision
    end)
    for offset=1,#expected do
        local cell = dfhack.screen.readTile(x + offset - 1, y)
        assert.equals(expected:byte(offset), cell and cell.ch,
            ('tooltip text %q mismatch at offset %d'):format(expected, offset))
    end
end

---Returns a stable character signature for one native panel.
---@param capture dwarfspec.ScreenCapture
---@param bounds {x1: integer, y1: integer, x2: integer, y2: integer}
---@return string
local function panel_signature(capture, bounds)
    local chars = {}
    for y=bounds.y1,bounds.y2 do
        for x=bounds.x1,bounds.x2 do
            local cell = captured_cell(capture, x, y)
            chars[#chars + 1] = tostring(cell and cell.ch or -1)
        end
    end
    return table.concat(chars, ',')
end

---Asserts that one production-derived row contains rendered native text.
---@param capture dwarfspec.ScreenCapture
---@param x1 integer
---@param x2 integer
---@param y integer
---@param description string
local function assert_rendered_row(capture, x1, x2, y, description)
    for x=x1,x2 do
        local cell = captured_cell(capture, x, y)
        if cell and cell.ch and cell.ch ~= 0 and cell.ch ~= 32 then return end
    end
    error(description)
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
    ds.await('selection indicator renders on the native route header', function()
        local capture = capture_panel('minecart_selection_indicator',
            overlay.layout.bounds)
        local tile = captured_cell(capture, overlay.layout:get_indicator_x(), y)
        local color = tile and tile.fg + (tile.bold and 8 or 0) or nil
        return tile and tile.ch == 16 and color == COLOR_YELLOW
    end)
end

---Asserts that every cell in the Premium recenter asset reached the screen.
---@param action dwarfui.AssetButton
local function assert_recenter_asset(action)
    local body = assert(action.frame_body,
        'production recenter action has no rendered body')
    assert.equals(3, body.width)
    assert.equals(3, body.height)
    local capture = ds.capture_screen('minecart_recenter_action', {
        max_width=body.x2 + 1,
        max_height=body.y2 + 1,
    })
    for y=0,2 do
        for x=0,2 do
            local expected = assert(dfhack.screen.findGraphicsTile(
                'INTERFACE_BITS', 32 + x, y),
                ('recenter asset cell %d,%d is unavailable'):format(x, y))
            local actual = assert(captured_cell(capture,
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
    local capture = ds.capture_screen('minecart_marker_label', {
        max_width=marker.label_x + #marker.label,
        max_height=marker.label_y + 1,
    })
    for offset=1,#marker.label do
        local tile = captured_cell(capture,
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
        local saved = {
            indicator=copy_coord(df.global.game.main_interface.recenter_indicator_m),
        }
        local hauling, overlay, native_subject, rail_subject, surface_subject
        local route_fixture
        local zoom_subject
        local rail, action
        local initial_scroll, initial_selection, initially_open
        local initial_overlay_enabled
        local paint_tile_spy
        local ok, failure = xpcall(function()
            -- Mount the real fortress screen as the input subject for the
            -- DwarfUI route-overlay behavior exercised below.
            native_subject = ds.mountNativeScreen()
            initial_overlay_enabled =
                require('plugins.overlay').isOverlayEnabled(
                    REGISTERED_WIDGET)
            assert.is_true(initial_overlay_enabled,
                'production marker overlay must begin enabled')
            initially_open = ds.hasFocus('dwarfmode/Hauling')
            local initial_view_pos = ds.getViewPos()
            -- The production zoom action writes the native viewport directly.
            -- Claim its original value through DwarfSpec before that happens.
            ds.setViewPos(initial_view_pos)

            -- Establish a known native focus through the same mounted input
            -- path used for every later click and wheel event.
            if initially_open then
                ds.input('LEAVESCREEN')
                ds.await('pre-existing Hauling menu closes', function()
                    return ds.hasFocus('dwarfmode/Default')
                end)
            end

            route_fixture = MinecartRouteFixture.create()

            local overlay_source = {
                source='overlay',
                overlay=REGISTERED_WIDGET,
            }
            ds.input('D_HAULING')
            ds.await('native Hauling menu opens', function()
                return ds.hasFocus('dwarfmode/Hauling')
            end)
            assert.is_true(ds.hasFocus('dwarfmode/Hauling'),
                'borrowed native screen did not report Hauling focus')
            hauling = assert(df.global.plotinfo.hauling,
                'native Hauling state is unavailable')
            initial_scroll = hauling.scroll_position
            -- Select the existing registry-owned controls after they observe
            -- Hauling and cache the rendered native panel bounds.
            ds.await('registered minecart controls observe Hauling', function()
                local rail_ok, selected_rail = pcall(ds.get,
                    'stop_action_rail', overlay_source)
                local surface_ok, selected_surface = pcall(ds.get,
                    'stop_action_rail/surface', overlay_source)
                local zoom_ok, selected_zoom = pcall(ds.get,
                    'stop_action_rail/surface/recenter', overlay_source)
                if not rail_ok or not surface_ok or not zoom_ok then
                    return false
                end
                local selected_overlay = selected_rail:raw().parent_view
                if not selected_overlay or not selected_overlay.layout.bounds or
                        not selected_overlay.layout:is_supported_focus(
                            selected_overlay.focus_provider()) then
                    return false
                end
                rail_subject, surface_subject, zoom_subject =
                    selected_rail, selected_surface, selected_zoom
                return true
            end)
            rail = rail_subject:raw()
            action = zoom_subject:raw()
            overlay = assert(rail.parent_view,
                'selected rail is not attached to its registered overlay')
            assert.equals(reqscript('dwarfui/widgets/hover_action_rail').
                HoverActionRail, getmetatable(rail),
                'selected overlay control is not the production rail')
            initial_selection = overlay.selection:get_selected_route_id()
            -- Premium keep-lower map glyphs compose over the base map tile,
            -- so readTile() exposes the base graphic. Observe DFHack's final
            -- paint call without replacing or bypassing the real renderer.
            paint_tile_spy = spy.on(dfhack.screen, 'paintTile')
            local header, stop = find_visible_header_and_stop(hauling,
                overlay.layout)
            local other_header = find_other_visible_header(hauling,
                overlay.layout, stop.route.id)
            local initial_capture = capture_panel('minecart_native_rows',
                overlay.layout.bounds)
            assert_rendered_row(initial_capture, overlay.layout.bounds.x1,
                overlay.layout.bounds.x2, header.y,
                'native route header has no rendered text')
            assert_rendered_row(initial_capture, stop.x1, stop.x2,
                stop.y1 + 1, 'native stop row has no rendered text')

            -- Route headers are never hover targets.
            ds.move_pointer(header.x, header.y)
            assert.is_false(surface_subject:inspect().visible,
                'route header incorrectly rendered the stop action rail')
            ds.mouseInput(ds.EMouseButton.LEFT)
            assert_selection_indicator(overlay, hauling, header.route.id)

            -- Number, label, and final native-list content cells resolve the
            -- same rendered three-row action rail.
            for _, y in ipairs({stop.y1, stop.y1 + 1, stop.y2}) do
                for _, x in ipairs({stop.x1, stop.x1 + 2, stop.x2}) do
                    ds.move_pointer(x, y)
                    local state = surface_subject:inspect()
                    assert.is_true(state.visible,
                        ('stop cell %d,%d did not render the action rail')
                            :format(x, y))
                    assert.equals(stop.y1, state.frame.y1,
                        'action rail is not aligned with the hovered stop top')
                    assert.equals(stop.y2, state.frame.y2,
                        'action rail is not aligned with the hovered stop bottom')
                end
            end
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
            assert.is_equal(action, rail.action_widgets[1],
                'selected zoom control is not the rendered rail action')
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
            local surface_state = surface_subject:inspect()
            assert.is_true(surface_state.visible,
                'selected action-rail surface is not rendered')
            assert.same(surface_bounds, surface_state.frame,
                'selected action-rail surface is not at its row-relative frame')
            assert.same({page='INTERFACE_BITS', x=32, y=0}, action.asset,
                'production recenter action uses the wrong graphics asset')
            assert.equals(3, #action.chars)
            assert.equals(3, #action.chars[1])

            -- Select a different route first so the following native stop-row
            -- click must visibly change the selection back to this stop's route.
            ds.move_pointer(other_header.x, other_header.y)
            ds.mouseInput(ds.EMouseButton.LEFT)
            assert_selection_indicator(overlay, hauling, other_header.route.id)
            ds.move_pointer(stop.x1 + 2, stop.y1 + 1)
            assert.is_true(surface_subject:inspect().visible,
                'stop action rail did not return after another route selection')
            ds.mouseInput(ds.EMouseButton.LEFT)
            assert_selection_indicator(overlay, hauling, stop.route.id)
            assert_recenter_asset(action)

            -- Cross from the stop to the action surface without losing the
            -- target, publish its registered tooltip intent, then click it.
            zoom_subject:move_pointer()
            assert.is_true(surface_subject:inspect().visible,
                'pointer transfer from stop to rail closed the rendered rail')
            ds.await('zoom action tooltip intent is published by the service',
                function()
                    local tooltip_state = ds.tooltip_state()
                    return tooltip_state.target == action and
                        tooltip_state.intent and
                        tooltip_state.intent.text ==
                            'Zoom to this stop'
                end)
            local before_route_id, before_stop_id = stop.route.id, stop.stop.id
            local before_pos = copy_coord(stop.stop.pos)
            assert.is_false(initial_view_pos.z == before_pos.z,
                'prepared save must begin on a different z-level from the ' ..
                    'first clicked stop')
            local before_route_object = hauling.view_routes[stop.index]
            local before_stop_object = hauling.view_stops[stop.index]
            local before_route_rows, before_stop_rows =
                #hauling.view_routes, #hauling.view_stops
            zoom_subject:click()
            assert_centered_and_highlighted(before_pos,
                'production rail click centers and highlights the stop')
            assert.equals(before_pos.z, df.global.window_z,
                'first production rail click did not change z-level')
            zoom_subject:click()
            assert_centered_and_highlighted(before_pos,
                'production rail click on the current z-level changed target')
            local resolved_after_zoom = stop.route
            assert_selection_indicator(overlay, hauling, before_route_id)
            ds.await('native map viewport applies the zoomed stop origin',
                function()
                    local corner = df.global.world.viewport.corner
                    return corner.x == df.global.window_x and
                        corner.y == df.global.window_y and
                        corner.z == df.global.window_z
                end)
            -- DwarfSpec centers the real tile and places the native pointer
            -- over it. Reproject after the camera movement.
            ds.move_pointer(before_pos, ds.EPointerSpace.WORLD_TILE)
            local marker = find_stop_marker(overlay.projection:project(
                resolved_after_zoom, overlay.viewport_provider()), stop.stop)
            assert.equals(MarkerKind.SAME_Z, marker.marker_kind)
            assert.equals(string.char(9), marker.marker_glyph)
            assert.same(expected_premium_ui_position(before_pos),
                marker.screen_pos,
                'marker does not use the Premium world-to-UI transform')
            assert.equals(marker.screen_pos.x, marker.label_x)
            assert.equals(marker.screen_pos.y + 2, marker.label_y)
            assert.is_true(marker.label_x >= overlay.frame_body.x1 and
                marker.label_x + #marker.label - 1 <= overlay.frame_body.x2 and
                marker.label_y >= overlay.frame_body.y1 and
                marker.label_y <= overlay.frame_body.y2,
                ('marker label %d,%d-%d is outside overlay body %d,%d-%d,%d')
                    :format(marker.label_x, marker.label_y,
                        marker.label_x + #marker.label - 1,
                        overlay.frame_body.x1, overlay.frame_body.y1,
                        overlay.frame_body.x2, overlay.frame_body.y2))
            ds.move_pointer(header.x, header.y)
            assert_rendered_marker(marker, paint_tile_spy)
            assert_rendered_marker_label(marker)

            local map_handle = assert(
                overlay.map_tooltip_handles[stop.stop.id],
                'same-z marker did not register its exact native tile')
            ds.move_pointer(before_pos, ds.EPointerSpace.WORLD_TILE)
            local hover_screen_x, hover_screen_y =
                dfhack.screen.getMousePos()
            ds.await('native marker publishes its map-tile tooltip',
                function()
                    local state = ds.tooltip_state()
                    return state.target == map_handle and state.intent and
                        state.intent.text == stop.stop.name
                end)
            local sampled_pos = assert(dfhack.gui.getMousePos(),
                'physical marker pointer has no native map position')
            assert.same(before_pos, copy_coord(sampled_pos),
                'physical marker pointer did not sample the native stop tile')
            local map_state = ds.tooltip_state()
            assert.is_equal(map_handle, map_state.target)
            assert.equals(hover_screen_x, map_state.intent.anchor_x)
            assert.equals(hover_screen_y, map_state.intent.anchor_y)
            assert.equals(stop.stop.name, marker.name)
            assert_rendered_tooltip_text(map_state.intent, stop.stop.name)

            -- Recenter the same x/y on another z-level. The projected marker
            -- remains visible, but its exact-tile registration clears.
            local off_z = before_pos.z + 1 < df.global.world.map.z_count and
                before_pos.z + 1 or before_pos.z - 1
            assert.is_true(off_z >= 0 and off_z ~= before_pos.z,
                'prepared map requires an adjacent z-level')
            ds.move_pointer({
                x=before_pos.x,
                y=before_pos.y,
                z=off_z,
            }, ds.EPointerSpace.WORLD_TILE)
            local off_z_marker = find_stop_marker(
                overlay.projection:project(resolved_after_zoom,
                    overlay.viewport_provider()), stop.stop)
            assert.is_false(
                off_z_marker.marker_kind == MarkerKind.SAME_Z,
                'different-z marker retained same-z marker kind')
            assert.equals(marker.screen_pos.x, off_z_marker.screen_pos.x,
                'z-only viewport change moved the projected marker x')
            assert.equals(marker.screen_pos.y, off_z_marker.screen_pos.y,
                'z-only viewport change moved the projected marker y')
            local off_z_state = ds.tooltip_state()
            assert.is_nil(overlay.map_tooltip_handles[stop.stop.id])
            assert.is_nil(off_z_state.target)
            assert.is_nil(off_z_state.intent)
            local off_z_sample = assert(dfhack.gui.getMousePos(),
                'off-z physical pointer has no native map position')
            assert.same({x=before_pos.x, y=before_pos.y, z=off_z},
                copy_coord(off_z_sample))
            assert_rendered_marker(off_z_marker, paint_tile_spy)

            ds.move_pointer(before_pos, ds.EPointerSpace.WORLD_TILE)
            marker = find_stop_marker(overlay.projection:project(
                resolved_after_zoom, overlay.viewport_provider()), stop.stop)
            map_handle = assert(overlay.map_tooltip_handles[stop.stop.id],
                'same-z registration did not return after z restoration')
            ds.await('same-z marker tooltip returns after z restoration',
                function()
                    local state = ds.tooltip_state()
                    return state.target == map_handle and state.intent and
                        state.intent.text == stop.stop.name
                end)

            -- The DwarfUI-owned action rail is painted over the map. Its
            -- widget target takes precedence over any map tile beneath it.
            ds.move_pointer(stop.x1 + 2, stop.y1 + 1)
            assert.is_true(surface_subject:inspect().visible,
                'stop row did not reopen the action rail for occlusion')
            zoom_subject:move_pointer()
            ds.await('DwarfUI surface occludes the map tooltip', function()
                local state = ds.tooltip_state()
                return state.target == action and state.intent and
                    state.intent.text == 'Zoom to this stop'
            end)

            overlay:clear_selection()
            assert.is_nil(overlay.selection:get_selected_route_id())
            assert.is_nil(overlay.map_tooltip_handles[stop.stop.id],
                'selection clear retained a native map target')
            local cleared_state = ds.tooltip_state()
            assert.is_false(cleared_state.target == map_handle,
                'selection clear retained the active native map target')
            assert.is_false(cleared_state.intent and
                cleared_state.intent.text == stop.stop.name,
                'selection clear retained the native map tooltip intent')

            ds.move_pointer(stop.x1 + 2, stop.y1 + 1)
            ds.mouseInput(ds.EMouseButton.LEFT)
            assert_selection_indicator(
                overlay, hauling, stop.route.id)
            assert.is_table(overlay.map_tooltip_handles[stop.stop.id],
                'native route reselection did not restore map targets')

            -- Pan the real map a few tiles while keeping this stop visible,
            -- then prove the registered overlay follows the native viewport.
            local pan_x = before_pos.x >= 4 and before_pos.x - 4 or
                before_pos.x + 4
            local pan_origin_x, pan_origin_y = expected_center_origin{
                x=pan_x, y=before_pos.y, z=before_pos.z,
            }
            ds.setViewPos({
                x=pan_origin_x, y=pan_origin_y, z=before_pos.z,
            }, ds.EScreenOrigin.TOP_LEFT)
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
            assert.is_equal(before_route_object,
                hauling.view_routes[stop.index])
            assert.is_equal(before_stop_object,
                hauling.view_stops[stop.index])
            assert.equals(before_route_rows, #hauling.view_routes)
            assert.equals(before_stop_rows, #hauling.view_stops)
            assert.equals(initial_scroll, hauling.scroll_position)
            assert.is_true(ds.hasFocus('dwarfmode/Hauling'),
                'zoom click closed Hauling')

            -- Wheel input over the rail belongs to the rail and must neither
            -- scroll the list nor change the map z-level.
            ds.move_pointer(rail.rail_bounds.x2, rail.rail_bounds.y1 + 1)
            local z_before_wheel, scroll_before_wheel = df.global.window_z,
                hauling.scroll_position
            ds.mouseInput(ds.EMouseButton.SCROLL_DOWN)
            assert.equals(z_before_wheel, df.global.window_z)
            assert.equals(scroll_before_wheel, hauling.scroll_position)

            -- Native scrolling occurs only while the actual pointer is over
            -- the native list. Find a newly occupied row and prove a later
            -- rail click targets that current stop, not the old one.
            ds.move_pointer(stop.x1 + 2, stop.y1 + 1)
            local before_scroll_capture = capture_panel(
                'minecart_rows_before_scroll', overlay.layout.bounds)
            local before_scroll_signature = panel_signature(
                before_scroll_capture, overlay.layout.bounds)
            local moved_stop
            for _=1,16 do
                local before_scroll = hauling.scroll_position
                -- DwarfSpec dispatches the wheel at its current virtual pointer
                -- position and mirrors that position to native mouse input.
                ds.mouseInput(ds.EMouseButton.SCROLL_DOWN)
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
            local after_scroll_capture = capture_panel(
                'minecart_rows_after_scroll', overlay.layout.bounds)
            assert.is_false(before_scroll_signature ==
                panel_signature(after_scroll_capture, overlay.layout.bounds),
                'native list state changed without changing its rendered rows')
            assert_rendered_row(after_scroll_capture, overlay.layout.bounds.x1,
                overlay.layout.bounds.x2, moved_stop.y,
                'scrolled native row has no rendered text')
            assert.is_false(same_coord(before_pos, moved_stop.stop.pos),
                'scrolled replacement stop must occupy a distinct world tile')
            assert.is_true(surface_subject:inspect().visible,
                'rail did not rebind to the newly visible native stop')
            ds.move_pointer(rail.rail_bounds.x2, rail.rail_bounds.y1 + 1)
            zoom_subject:click()
            assert_centered_and_highlighted(copy_coord(moved_stop.stop.pos),
                'rebound rail click targets the new native stop')
            assert.is_true(next(overlay.map_tooltip_handles) ~= nil,
                'selected route has no map targets before menu close')

            ds.input('LEAVESCREEN')
            ds.await('native Hauling menu closes', function()
                return ds.hasFocus('dwarfmode/Default')
            end)
            ds.await('rail clears after native menu closure', function()
                return overlay.stop_rail:get_target() == nil and
                    not overlay.stop_rail.surface.visible and
                    next(overlay.map_tooltip_handles) == nil and
                    ds.tooltip_state().intent == nil
            end)
            assert.is_false(overlay.layout:is_supported_focus(
                overlay.focus_provider()),
                'registered overlay remained eligible after Hauling closed')

            -- Recreate native registrations, then prove configuration and
            -- module lifecycle boundaries retire their owning handles.
            hauling.scroll_position = initial_scroll
            ds.input('D_HAULING')
            ds.await('Hauling reopens for overlay lifecycle checks',
                function()
                    return ds.hasFocus('dwarfmode/Hauling')
                end)
            ds.move_pointer(
                copy_coord(stop.stop.pos), ds.EPointerSpace.WORLD_TILE)
            ds.move_pointer(stop.x1 + 2, stop.y1 + 1)
            ds.mouseInput(ds.EMouseButton.LEFT)
            assert.is_true(next(overlay.map_tooltip_handles) ~= nil,
                'native reselection did not create lifecycle test handles')

            dfhack.run_command(
                'overlay', 'disable', REGISTERED_WIDGET)
            ds.await('overlay disable retires native map handles',
                function()
                    return next(overlay.map_tooltip_handles) == nil and
                        ds.tooltip_state().intent == nil
                end)
            dfhack.run_command(
                'overlay', 'enable', REGISTERED_WIDGET)

            ds.await('reenabled marker overlay returns', function()
                local rail_ok, candidate = pcall(
                    ds.get, 'stop_action_rail', overlay_source)
                if not rail_ok then return false end
                local candidate_overlay = candidate:raw().parent_view
                if not candidate_overlay or
                        not candidate_overlay.layout.bounds then
                    return false
                end
                overlay = candidate_overlay
                return true
            end)
            hauling.scroll_position = initial_scroll
            ds.move_pointer(
                copy_coord(stop.stop.pos), ds.EPointerSpace.WORLD_TILE)
            ds.move_pointer(stop.x1 + 2, stop.y1 + 1)
            ds.mouseInput(ds.EMouseButton.LEFT)
            assert.is_true(next(overlay.map_tooltip_handles) ~= nil,
                'reenabled overlay did not recreate native map handles')

            local pre_reload_overlay = overlay
            dfhack.run_command('dwarfui', 'reload')
            ds.await('reload retires old native map handles', function()
                return next(pre_reload_overlay.map_tooltip_handles) == nil and
                    ds.tooltip_state().intent == nil
            end)
            ds.await('reloaded marker overlay returns', function()
                local rail_ok, candidate = pcall(
                    ds.get, 'stop_action_rail', overlay_source)
                if not rail_ok then return false end
                local candidate_overlay = candidate:raw().parent_view
                if not candidate_overlay or
                        candidate_overlay == pre_reload_overlay then
                    return false
                end
                overlay = candidate_overlay
                return true
            end)
            assert.is_nil(overlay.selection:get_selected_route_id())
            assert.is_nil(next(overlay.map_tooltip_handles))
        end, debug.traceback)

        if hauling then hauling.scroll_position = initial_scroll end
        local indicator = df.global.game.main_interface.recenter_indicator_m
        indicator.x, indicator.y, indicator.z = saved.indicator.x,
            saved.indicator.y, saved.indicator.z
        if initial_overlay_enabled ~= nil then
            local overlay_plugin = require('plugins.overlay')
            local enabled =
                overlay_plugin.isOverlayEnabled(REGISTERED_WIDGET)
            if initial_overlay_enabled and not enabled then
                dfhack.run_command(
                    'overlay', 'enable', REGISTERED_WIDGET)
            elseif not initial_overlay_enabled and enabled then
                dfhack.run_command(
                    'overlay', 'disable', REGISTERED_WIDGET)
            end
        end
        if overlay then
            overlay:clear_overlay_state()
            overlay.selection.selected_route_id = initial_selection
        end
        if paint_tile_spy then paint_tile_spy:revert() end
        local is_open = native_subject and ds.hasFocus('dwarfmode/Hauling')
        if native_subject and initially_open and not is_open then
            ds.input('D_HAULING')
            ds.await('original Hauling menu reopens', function()
                return ds.hasFocus('dwarfmode/Hauling')
            end)
        elseif native_subject and not initially_open and is_open then
            ds.input('LEAVESCREEN')
            ds.await('test Hauling menu closes', function()
                return ds.hasFocus('dwarfmode/Default')
            end)
        end
        MinecartRouteFixture.destroy(route_fixture)
        assert.same(saved.indicator, copy_coord(
            df.global.game.main_interface.recenter_indicator_m))
        assert.is_true(ok, failure)
    end)
end)
