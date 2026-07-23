-- Live component contract for minecart route markers.
-- Opens dwarfmode/Hauling from the active fortress, then requires a visible
-- route header and at least one stop. It never mutates player-owned route data.

local guidm = require('gui.dwarfmode')
local widgets = require('gui.widgets')

local REGISTERED_WIDGET =
    'dwarfui-minecart-route-markers.minecart_route_markers'

---Returns the first visible native route header that has a real stop.
---@param hauling df.hauling_handlerst
---@return df.hauling_route
---@return integer
local function find_visible_route(hauling)
    local index = hauling.scroll_position
    local count = #hauling.view_routes
    while index < count do
        local route = hauling.view_routes[index]
        if not (hauling.view_stops and hauling.view_stops[index]) and
                route.stops and route.stops[0] then
            return route, index
        end
        index = index + 1
    end
    error('prepared save requires a visible Minecart Route header with a stop')
end

---Snapshots the native unit-card state that Hauling setup may temporarily close.
---@return table
local function snapshot_unit_card()
    local sheets = df.global.game.main_interface.view_sheets
    local ids = {}
    for _, id in ipairs(sheets.viewing_unid) do table.insert(ids, id) end
    return {
        open=sheets.open, context=sheets.context, active_sheet=sheets.active_sheet,
        active_id=sheets.active_id, viewing_x=sheets.viewing_x,
        viewing_y=sheets.viewing_y, viewing_z=sheets.viewing_z,
        scroll_position=sheets.scroll_position, active_sub_tab=sheets.active_sub_tab,
        last_tick_update=sheets.last_tick_update, viewing_unid=ids,
    }
end

---Restores a previously open native unit card without changing its subject.
---@param saved table
local function restore_unit_card(saved)
    local sheets = df.global.game.main_interface.view_sheets
    sheets.open, sheets.context, sheets.active_sheet = saved.open, saved.context,
        saved.active_sheet
    sheets.active_id, sheets.viewing_x, sheets.viewing_y, sheets.viewing_z =
        saved.active_id, saved.viewing_x, saved.viewing_y, saved.viewing_z
    sheets.scroll_position, sheets.active_sub_tab, sheets.last_tick_update =
        saved.scroll_position, saved.active_sub_tab, saved.last_tick_update
    sheets.viewing_unid:resize(0)
    for _, id in ipairs(saved.viewing_unid) do sheets.viewing_unid:insert('#', id) end
end

---Asserts that rendered screen cells contain the expected text and color.
---@param x integer
---@param y integer
---@param text string
---@param color integer
---@param description string
local function assert_rendered_text(x, y, text, color, description)
    ds.await(description, function()
        for offset=1,#text do
            local tile = dfhack.screen.readTile(x + offset - 1, y)
            local rendered_color = tile and
                tile.fg + (tile.bold and 8 or 0) or nil
            if not tile or tile.ch ~= text:byte(offset) or
                    rendered_color ~= color then
                return false
            end
        end
        return true
    end)
    for offset=1,#text do
        local tile = assert(dfhack.screen.readTile(x + offset - 1, y),
            ('%s: screen cell is unavailable'):format(description))
        local rendered_color = tile.fg + (tile.bold and 8 or 0)
        assert.equals(text:byte(offset), tile.ch,
            ('%s: unexpected glyph at %d,%d (fg=%s)'):format(
                description, x + offset - 1, y, tostring(rendered_color)))
        assert.equals(color, rendered_color,
            ('%s: unexpected color at %d,%d'):format(
                description, x + offset - 1, y))
    end
end

---Returns the projected descriptor for one real native stop.
---@param markers dwarfui.MinecartRouteMarkerDescriptor[]
---@param stop df.hauling_stop
---@return dwarfui.MinecartRouteMarkerDescriptor
local function find_stop_marker(markers, stop)
    for _, marker in ipairs(markers) do
        if marker.stop_id == stop.id then return marker end
    end
    error(('native route stop was not projected: %s'):format(stop.id))
end

---Independently resolves the interface-layer cell occupied by a world tile.
---Premium graphics scales the map independently from the text interface.
---@param pos df.coord
---@param viewport gui.dwarfmode.Viewport
---@return df.coord
local function expected_stop_ui_position(pos, viewport)
    if not dfhack.screen.inGraphicsMode() then
        return viewport:tileToScreen(pos)
    end
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

---Centers Premium's native world-tile viewport on a stop and waits until its
---corner reflects the requested movement before interface projection begins.
---@param pos df.coord
local function center_native_viewport_on(pos)
    local native_viewport = df.global.world.viewport
    local world_width = native_viewport.max_x
    local world_height = native_viewport.max_y
    if dfhack.screen.inGraphicsMode() then
        local gps = df.global.gps
        local map_tile_pixels = gps.viewport_zoom_factor // 4
        world_width = math.max(1,
            native_viewport.max_x * gps.tile_pixel_x // map_tile_pixels)
        world_height = math.max(1,
            native_viewport.max_y * gps.tile_pixel_y // map_tile_pixels)
    end
    local target_x = pos.x - world_width // 2
    local target_y = pos.y - world_height // 2
    df.global.window_x = target_x
    df.global.window_y = target_y
    df.global.window_z = pos.z
    ds.await('native map viewport centers on the selected route stop',
        function()
            local corner = df.global.world.viewport.corner
            return corner.x == target_x and corner.y == target_y and
                corner.z == pos.z
        end)
end

---Asserts that the map compositor received a full-tile marker pen that keeps
---the native map texture as its transparent background.
---@param calls table[]
---@param marker dwarfui.MinecartRouteMarkerDescriptor
---@param description string
local function assert_composited_marker(calls, marker, description)
    ds.wait_frames(2)
    for index=#calls,1,-1 do
        local call = calls[index]
        if call.x == marker.world_pos.x and call.y == marker.world_pos.y and
                call.pen and call.pen.ch == marker.marker_glyph:byte() and
                call.pen.fg == marker.marker_pen.fg and
                call.pen.keep_lower == true then
            return
        end
    end
    error(('%s: expected transparent glyph %d with color %d at %d,%d')
        :format(description, marker.marker_glyph:byte(),
            marker.marker_pen.fg, marker.world_pos.x, marker.world_pos.y))
end

describe('native Minecart Route marker overlay', function()
    it('selects a real route and renders its indicator, markers, and labels',
            function()
        local gps = df.global.gps
        -- Preserve every piece of native UI state that this live interaction
        -- changes so the prepared fortress is left exactly as it was found.
        local saved = {
            mouse_x=gps.mouse_x, mouse_y=gps.mouse_y,
            precise_mouse_x=gps.precise_mouse_x,
            precise_mouse_y=gps.precise_mouse_y,
            window_x=df.global.window_x, window_y=df.global.window_y,
            window_z=df.global.window_z,
            mouse_focus=df.global.enabler.mouse_focus,
            tracking_on=df.global.enabler.tracking_on,
        }
        local saved_unit_card = snapshot_unit_card()
        local screen
        local hauling
        local root
        local old_focus_provider
        local old_map_overlay_renderer
        local map_render_calls = {}
        local native_focus
        local ok, failure = xpcall(function()
            -- Normalize the native fortress UI before opening the Hauling menu
            -- through the same input binding available to a player.
            screen = assert(dfhack.gui.getDFViewscreen(true),
                'prepared save must have a fortress viewscreen')
            if saved_unit_card.open then
                df.global.game.main_interface.view_sheets.open = false
                ds.await('native unit card closes', function()
                    return dfhack.gui.matchFocusString('dwarfmode/Default',
                        dfhack.gui.getDFViewscreen(true))
                end)
            end
            if dfhack.gui.matchFocusString('dwarfmode/Hauling', screen) then
                require('gui').simulateInput(screen, 'LEAVESCREEN')
                ds.await('pre-existing Hauling menu closes', function()
                    return dfhack.gui.matchFocusString('dwarfmode/Default',
                        dfhack.gui.getDFViewscreen(true))
                end)
            end
            screen = assert(dfhack.gui.getDFViewscreen(true),
                'fortress viewscreen disappeared before opening Hauling')
            require('gui').simulateInput(screen, 'D_HAULING')
            ds.await('native Hauling menu opens', function()
                return dfhack.gui.matchFocusString('dwarfmode/Hauling',
                    dfhack.gui.getDFViewscreen(true))
            end)
            screen = assert(dfhack.gui.getDFViewscreen(true),
                'Hauling viewscreen disappeared after opening')
            hauling = assert(df.global.plotinfo.hauling,
                'prepared save has no plotinfo.hauling state')
            saved.scroll_position = hauling.scroll_position
            native_focus = dfhack.gui.getCurFocus()
            assert.is_table(native_focus,
                'DFHack must expose the native focus-string list')
            assert.is_true(require('utils').linear_index(native_focus,
                'dwarfmode/Hauling') ~= nil,
                'native focus list does not contain dwarfmode/Hauling')

            -- Add a transparent one-cell interaction target to the production
            -- component instance. DwarfSpec can then own the exact pointer
            -- position without replacing dfhack.screen.getMousePos in the test.
            dfhack.run_command('dwarfui reload')
            local MinecartRouteMarkersOverlay = reqscript(
                'dwarfui-minecart-route-markers').MinecartRouteMarkersOverlay
            local overlay_plugin = require('plugins.overlay')
            local overlay_state = overlay_plugin.get_state()
            local registered_entry = assert(overlay_state.db[REGISTERED_WIDGET],
                'production minecart-route overlay is not registered')
            assert.is_true(overlay_state.config[REGISTERED_WIDGET].enabled,
                'production minecart-route overlay is not enabled')
            local registered = registered_entry.widget
            assert.is_true(registered.visible,
                'production minecart-route overlay is not visible')
            ds.await('production overlay caches native Hauling bounds',
                function()
                    registered:ensure_menu_bounds()
                    return registered.layout.bounds ~= nil
                end)
            assert.is_table(registered.layout.bounds,
                'production overlay did not cache the native Hauling bounds')
            assert.is_true(registered.layout.bounds.x1 > 0,
                'native Hauling panel must not be mistaken for fullscreen x=0')
            assert.equals(registered.layout.bounds.x1 + 1,
                registered.layout:get_indicator_x(),
                'selection indicator must be inset one cell from the menu edge')

            -- Exercise the canonical registered widget with the real DFHack
            -- focus-list value and a pointer over actual native label text.
            -- Returning false proves the overlay leaves the click for native DF.
            local registered_route, registered_row =
                find_visible_route(hauling)
            local registered_y = registered.layout.first_row_top + 1 +
                (registered_row - hauling.scroll_position) *
                    registered.layout.row_height
            local registered_x = registered.layout.bounds.x1 + 2
            gps.mouse_x, gps.mouse_y = registered_x, registered_y
            gps.precise_mouse_x = registered_x * gps.tile_pixel_x + 1
            gps.precise_mouse_y = registered_y * gps.tile_pixel_y + 1
            registered:clear_selection()
            assert.is_false(overlay_plugin.feed_viewscreen_widgets(
                'viewscreen_dwarfmodest', screen, {_MOUSE_L=true}))
            assert.equals(registered_route.id,
                registered.selection:get_selected_route_id())
            local registered_indicator_y = assert(
                registered.layout:find_route_header_y(hauling,
                    registered_route.id, registered.focus_provider()),
                'registered route-label click did not expose its header') + 1
            assert_rendered_text(registered.layout:get_indicator_x(),
                registered_indicator_y, string.char(16), COLOR_YELLOW,
                'registered route-label click renders its selection indicator')

            -- A stop row must resolve to the same owning route and retain the
            -- header indicator, even though the stop itself has no indicator.
            local registered_stop_row
            for index=registered_row + 1,#hauling.view_routes - 1 do
                if hauling.view_routes[index].id ~= registered_route.id then
                    break
                end
                if hauling.view_stops[index] then
                    registered_stop_row = index
                    break
                end
            end
            assert.is_number(registered_stop_row,
                'visible registered route requires a visible stop row')
            registered_y = registered.layout.first_row_top + 1 +
                (registered_stop_row - hauling.scroll_position) *
                    registered.layout.row_height
            gps.mouse_x = registered_x
            gps.mouse_y = registered_y
            gps.precise_mouse_x = registered_x * gps.tile_pixel_x + 1
            gps.precise_mouse_y = registered_y * gps.tile_pixel_y + 1
            registered:clear_selection()
            assert.is_false(overlay_plugin.feed_viewscreen_widgets(
                'viewscreen_dwarfmodest', screen, {_MOUSE_L=true}))
            assert.equals(registered_route.id,
                registered.selection:get_selected_route_id())
            assert_rendered_text(registered.layout:get_indicator_x(),
                registered_indicator_y, string.char(16), COLOR_YELLOW,
                'registered stop-row click retains the route indicator')
            registered:clear_selection()

            local component = MinecartRouteMarkersOverlay{}
            local pointer_target = widgets.Panel{
                view_id='native_route_pointer_target',
                frame={l=6, t=11, w=1, h=1},
            }
            component:addviews{pointer_target}
            root = ds.mount(component, {
                backing_viewscreen=screen,
                initial_pause=false,
            }):raw()
            local pointer_subject = ds.get('native_route_pointer_target')
            old_focus_provider = root.focus_provider
            old_map_overlay_renderer = root.map_overlay_renderer
            root.map_overlay_renderer = function(callback, bounds)
                return old_map_overlay_renderer(function(pos, is_cursor)
                    local pen, glyph, tile = callback(pos, is_cursor)
                    if pen then
                        table.insert(map_render_calls, {
                            x=pos.x, y=pos.y, z=pos.z,
                            pen=pen, glyph=glyph, tile=tile,
                        })
                    end
                    return pen, glyph, tile
                end, bounds)
            end
            -- The DwarfSpec host becomes the immediate focus while mounted.
            -- Preserve the real native focus list captured from the backing
            -- Hauling menu instead of replacing it with a test-only string.
            root.focus_provider = function() return native_focus end
            root:ensure_menu_bounds()

            -- Prove the native route list receives wheel input only while the
            -- DwarfSpec-owned pointer is physically over that list.
            df.global.enabler.mouse_focus = true
            df.global.enabler.tracking_on = 1
            local native_x, native_y = ds.move_pointer(pointer_subject)
            gps.mouse_x, gps.mouse_y = native_x, native_y
            gps.precise_mouse_x = native_x * gps.tile_pixel_x + 1
            gps.precise_mouse_y = native_y * gps.tile_pixel_y + 1
            require('gui').simulateInput(screen, '_MOUSE_L')
            require('gui').simulateInput(screen, 'CONTEXT_SCROLL_DOWN')
            ds.wait_frames(1)
            assert.is_true(hauling.scroll_position > saved.scroll_position,
                ('native route list did not scroll under pointer %d,%d ' ..
                    '(before=%d, after=%d)'):format(native_x, native_y,
                    saved.scroll_position, hauling.scroll_position))

            -- Point at a real visible route header and click through the mounted
            -- production overlay, then verify its selected-route state.
            local route, row_index = find_visible_route(hauling)
            local stop = route.stops[0]
            pointer_target.frame.l = root.layout.list_x1 + 2
            pointer_target.frame.t = root.layout.first_row_top + 1 +
                (row_index - hauling.scroll_position) * root.layout.row_height
            root:updateLayout()
            ds.click(pointer_subject)
            assert.equals(route.id, root.selection:get_selected_route_id())

            -- Verify the selection glyph as rendered on the native Hauling
            -- route row, including its CP473 glyph and foreground color.
            local indicator_y = assert(root.layout:find_route_header_y(hauling,
                route.id, 'dwarfmode/Hauling'),
                'selected native route header is not visible') + 1
            assert_rendered_text(root.layout:get_indicator_x(), indicator_y,
                string.char(16), COLOR_YELLOW,
                'selected route indicator renders on the Hauling menu')

            -- A stale selection must clear safely before the real route is
            -- selected again for the world-marker rendering checks.
            root.selection.selected_route_id = -1
            assert.is_nil(root:resolve_selected_route())
            assert.is_nil(root.selection:get_selected_route_id())
            root.selection:select_route(route)

            -- Center the real game viewport on one stop and verify every visible
            -- same-z marker descriptor, label cell, and compositor call.
            center_native_viewport_on(stop.pos)
            local viewport = guidm.Viewport.get()
            local markers = root.projection:project(route, viewport)
            if #markers == 0 then
                local native_viewport = df.global.world.viewport
                local translated = expected_stop_ui_position(stop.pos, viewport)
                error(('centered stop was not UI-visible: stop=%s,%s,%s; ' ..
                    'window=%s,%s,%s; corner=%s,%s,%s; native_max=%s,%s; ' ..
                    'ui=%s,%s; interface=%s,%s')
                    :format(stop.pos.x, stop.pos.y, stop.pos.z,
                        df.global.window_x, df.global.window_y, viewport.z,
                        native_viewport.corner.x, native_viewport.corner.y,
                        native_viewport.corner.z, native_viewport.max_x,
                        native_viewport.max_y, translated.x, translated.y,
                        viewport.width, viewport.height))
            end
            local marker = find_stop_marker(markers, stop)
            assert.same(expected_stop_ui_position(stop.pos, viewport),
                marker.screen_pos)
            assert.equals(string.char(9), marker.marker_glyph,
                'same-z route stops must use the CP437 circle glyph')
            assert.equals(marker.screen_pos.x, marker.label_x)
            assert.equals(marker.screen_pos.y + 2, marker.label_y)
            assert.equals(stop.name, marker.name)
            assert.is_truthy(marker.label:find(stop.name, 1, true))
            for _, visible_marker in ipairs(markers) do
                assert_composited_marker(map_render_calls, visible_marker,
                    'visible route-stop indicator renders as a full map tile')
                assert_rendered_text(visible_marker.label_x,
                    visible_marker.label_y, visible_marker.label,
                    visible_marker.marker_pen.fg,
                    'visible route-stop label renders beside its marker')
            end

            -- Pan the actual native viewport by one world tile. The marker
            -- remains bound to the stop's world position, while its label must
            -- move to the newly translated interface-layer coordinate.
            local initial_label_x = marker.label_x
            local shifted_window_x = df.global.window_x + 1
            df.global.window_x = shifted_window_x
            ds.await('native map viewport applies the horizontal pan',
                function()
                    return df.global.world.viewport.corner.x ==
                        shifted_window_x
                end)
            local shifted_viewport = guidm.Viewport.get()
            local shifted_marker = find_stop_marker(
                root.projection:project(route, shifted_viewport), stop)
            assert.same(expected_stop_ui_position(stop.pos, shifted_viewport),
                shifted_marker.screen_pos)
            assert.not_equals(initial_label_x, shifted_marker.label_x,
                'route-stop label did not move with the native map viewport')
            assert.equals(shifted_marker.screen_pos.x, shifted_marker.label_x)
            assert.equals(shifted_marker.screen_pos.y + 2,
                shifted_marker.label_y)
            assert_rendered_text(shifted_marker.label_x,
                shifted_marker.label_y, shifted_marker.label,
                shifted_marker.marker_pen.fg,
                'route-stop label follows native horizontal map movement')
            assert_composited_marker(map_render_calls, shifted_marker,
                'route-stop indicator remains attached after map movement')

            -- Move the viewport one z-level away, when possible, and verify the
            -- directional marker and z-delta label rendering contract.
            local off_z = shifted_viewport:clip(nil, nil, math.max(0,
                math.min(shifted_viewport.z + 1,
                    df.global.world.map.z_count - 1)))
            if off_z.z ~= stop.pos.z and off_z:isVisibleXY(stop.pos) then
                off_z:set()
                local projected_markers = root.projection:project(route, off_z)
                local projected = find_stop_marker(projected_markers, stop)
                assert.not_equals('same_z', projected.marker_kind)
                assert.equals(stop.pos.z - off_z.z, projected.z_delta)
                assert.equals(projected.z_delta > 0 and string.char(30) or
                    string.char(31), projected.marker_glyph,
                    'off-z route stop must use a bold CP437 triangle glyph')
                for _, visible_marker in ipairs(projected_markers) do
                    assert_composited_marker(map_render_calls, visible_marker,
                        'off-z route-stop indicator renders directionally')
                    assert_rendered_text(visible_marker.label_x,
                        visible_marker.label_y, visible_marker.label,
                        visible_marker.marker_pen.fg,
                        'projected route-stop label renders with its z delta')
                end
            end
        end, debug.traceback)

        -- Restore native list, pointer, viewport, focus, overlay, and unit-card
        -- state even when an assertion above fails.
        if hauling and saved.scroll_position then
            hauling.scroll_position = saved.scroll_position
        end
        gps.mouse_x, gps.mouse_y = saved.mouse_x, saved.mouse_y
        gps.precise_mouse_x, gps.precise_mouse_y = saved.precise_mouse_x,
            saved.precise_mouse_y
        df.global.window_x, df.global.window_y, df.global.window_z =
            saved.window_x, saved.window_y, saved.window_z
        df.global.enabler.mouse_focus = saved.mouse_focus
        df.global.enabler.tracking_on = saved.tracking_on
        if root then
            root:clear_selection()
            root.focus_provider = old_focus_provider
            root.map_overlay_renderer = old_map_overlay_renderer
            ds.unmount()
        end
        local native_screen = dfhack.gui.getDFViewscreen(true)
        if native_screen and dfhack.gui.matchFocusString('dwarfmode/Hauling',
                native_screen) then
            require('gui').simulateInput(native_screen, 'LEAVESCREEN')
            ds.await('native Hauling menu closes', function()
                return dfhack.gui.matchFocusString('dwarfmode/Default',
                    dfhack.gui.getDFViewscreen(true))
            end)
        end
        restore_unit_card(saved_unit_card)
        assert.is_true(ok, failure)
    end)
end)
