-- Live component contract for minecart route markers.
-- Opens dwarfmode/Hauling from the active fortress. The prepared save requires
-- Premium graphics and a scrollable route list with visible stops at distinct
-- tiles so the graphics and rebound-button contracts can be proven. The test
-- never mutates player-owned route data.

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

---Returns a detached coordinate snapshot.
---@param pos {x: integer, y: integer, z: integer}
---@return {x: integer, y: integer, z: integer}
local function copy_coord(pos)
    return {x=pos.x, y=pos.y, z=pos.z}
end

---Returns whether two coordinates identify the same world tile.
---@param left {x: integer, y: integer, z: integer}
---@param right {x: integer, y: integer, z: integer}
---@return boolean
local function same_coord(left, right)
    return left.x == right.x and left.y == right.y and left.z == right.z
end

---Returns every fully visible flattened native row and its screen bounds.
---@param hauling df.hauling_handlerst
---@param layout dwarfui.MinecartRouteMenuLayout
---@return table[]
local function get_visible_native_rows(hauling, layout)
    local rows = {}
    local visible_count = math.max(0, math.floor(
        (layout.bounds.y2 - layout.first_row_top + 1) /
            layout.row_height))
    for visible_index=0,visible_count - 1 do
        local row_index = hauling.scroll_position + visible_index
        local route = hauling.view_routes[row_index]
        if route then
            table.insert(rows, {
                row_index=row_index,
                route=route,
                stop=hauling.view_stops[row_index],
                y1=layout.first_row_top +
                    visible_index * layout.row_height,
                y2=layout.first_row_top +
                    (visible_index + 1) * layout.row_height - 1,
            })
        end
    end
    return rows
end

---Verifies that production recenter buttons exist only on real stop rows and
---that all nine cells use the vanilla graphic over the native panel background.
---@param component dwarfui.MinecartRouteMarkersOverlay
---@param hauling df.hauling_handlerst
---@param AssetButton dwarfui.AssetButton
---@param description string
---@param verify_graphics? boolean
---@return dwarfui.AssetButton[]
local function assert_rendered_stop_buttons(
        component, hauling, AssetButton, description, verify_graphics)
    component:refresh_stop_actions(hauling)
    ds.wait_frames(2)

    local rows = get_visible_native_rows(hauling, component.layout)
    local stop_rows = {}
    local header_rows = {}
    for _, row in ipairs(rows) do
        if row.stop then
            stop_rows[row.row_index] = row
        else
            header_rows[row.row_index] = row
        end
    end

    local buttons = component.stop_action_pool:get_active_buttons()
    local stop_count = 0
    for _ in pairs(stop_rows) do stop_count = stop_count + 1 end
    assert.equals(stop_count, #buttons,
        description .. ': visible stop rows and buttons differ')
    assert.is_true(#buttons > 0,
        description .. ': prepared save requires a visible minecart stop row')
    if verify_graphics ~= false then
        assert.is_true(dfhack.screen.inGraphicsMode(),
            description .. ': graphics-cell proof requires Premium graphics mode')
    end

    local covered_stop_rows = {}
    for _, button in ipairs(buttons) do
        assert.equals(AssetButton, getmetatable(button),
            description .. ': stop action is not the production AssetButton')
        local descriptor = assert(button.action_descriptor,
            description .. ': visible button has no native row binding')
        assert.equals('recenter', descriptor.action_id,
            description .. ': unexpected stop action')
        assert.is_nil(header_rows[descriptor.row_index],
            description .. ': a route-header row received an action button')
        local native_row = assert(stop_rows[descriptor.row_index],
            description .. ': button is not bound to a visible stop row')
        assert.equals(native_row.route.id, descriptor.route_id)
        assert.equals(native_row.stop.id, descriptor.stop_id)
        assert.equals(native_row.y1, descriptor.bounds.y1)
        assert.equals(native_row.y2, descriptor.bounds.y2)
        covered_stop_rows[descriptor.row_index] = true

        local button_cell_count = 0
        for _, token in ipairs(button.text) do
            if type(token) == 'table' then
                button_cell_count = button_cell_count + 1
                assert.is_true(token.tile.keep_lower,
                    description ..
                        ': normal button pen does not preserve the native panel')
                assert.is_true(token.htile.keep_lower,
                    description ..
                        ': hover button pen does not preserve the native panel')
            end
        end
        assert.equals(9, button_cell_count,
            description .. ': production button does not contain nine cells')

        if verify_graphics ~= false then
            for dy=0,2 do
                for dx=0,2 do
                    local expected_tile = assert(dfhack.screen.findGraphicsTile(
                        'INTERFACE_BITS', 32 + dx, dy),
                        description ..
                            ': STOCKS_RECENTER asset cell is unavailable')
                    local screen_pen = assert(dfhack.screen.readTile(
                        descriptor.bounds.x1 + dx, descriptor.bounds.y1 + dy),
                        description .. ': rendered button cell is unavailable')
                    assert.equals(expected_tile, screen_pen.tile,
                        ('%s: incorrect graphics tile at button cell %d,%d')
                            :format(description, dx + 1, dy + 1))
                end
            end
        end
    end
    for row_index in pairs(stop_rows) do
        assert.is_true(covered_stop_rows[row_index],
            description .. ': visible stop row has no recenter button')
    end
    return buttons
end

---Moves the standard DwarfSpec pointer target onto one exact screen cell.
---@param root dwarfui.MinecartRouteMarkersOverlay
---@param pointer_target widgets.Panel
---@param pointer_subject dwarfspec.Subject
---@param x integer
---@param y integer
---@return integer
---@return integer
local function move_pointer_to_cell(
        root, pointer_target, pointer_subject, x, y)
    pointer_target.frame.l = x
    pointer_target.frame.t = y
    root:updateLayout()
    local actual_x, actual_y = ds.move_pointer(pointer_subject)
    assert.equals(x, actual_x, 'DwarfSpec pointer x did not reach target cell')
    assert.equals(y, actual_y, 'DwarfSpec pointer y did not reach target cell')
    return actual_x, actual_y
end

---Clamps a requested map origin to the native fortress-map dimensions.
---@param x integer
---@param y integer
---@return integer
---@return integer
local function clamp_map_origin(x, y)
    local dims = dfhack.gui.getDwarfmodeViewDims()
    local width = dims.map_x2 - dims.map_x1 + 1
    local height = dims.map_y2 - dims.map_y1 + 1
    local max_x = math.max(0, df.global.world.map.x_count - width)
    local max_y = math.max(0, df.global.world.map.y_count - height)
    return math.max(0, math.min(x, max_x)),
        math.max(0, math.min(y, max_y))
end

---Returns the clamped map origin expected from DFHack's centered reveal call.
---@param pos {x: integer, y: integer, z: integer}
---@return integer
---@return integer
local function expected_centered_origin(pos)
    local dims = dfhack.gui.getDwarfmodeViewDims()
    local width = dims.map_x2 - dims.map_x1 + 1
    local height = dims.map_y2 - dims.map_y1 + 1
    return clamp_map_origin(pos.x - width // 2, pos.y - height // 2)
end

---Verifies the native viewport and pulsing recenter indicator after activation.
---@param pos {x: integer, y: integer, z: integer}
---@param description string
local function assert_centered_and_highlighted(pos, description)
    local expected_x, expected_y = expected_centered_origin(pos)
    ds.await(description, function()
        local indicator =
            df.global.game.main_interface.recenter_indicator_m
        local actual_x, actual_y =
            clamp_map_origin(df.global.window_x, df.global.window_y)
        return df.global.window_z == pos.z and actual_x == expected_x and
            actual_y == expected_y and indicator.x == pos.x and
            indicator.y == pos.y and indicator.z == pos.z
    end)
    local indicator = df.global.game.main_interface.recenter_indicator_m
    assert.same(pos, copy_coord(indicator),
        description .. ': native highlight targets the wrong tile')
end

---Returns current visible button bindings keyed by native stop ID.
---@param buttons dwarfui.AssetButton[]
---@return table<integer, table>
local function snapshot_button_bindings(buttons)
    local bindings = {}
    for _, button in ipairs(buttons) do
        local descriptor = assert(button.action_descriptor)
        bindings[descriptor.stop_id] = {
            button=button,
            row_index=descriptor.row_index,
            y1=descriptor.bounds.y1,
        }
    end
    return bindings
end

---Returns whether a retained native stop moved to a different rendered row.
---@param before table<integer, table>
---@param after table<integer, table>
---@return boolean
local function has_moved_binding(before, after)
    for stop_id, old_binding in pairs(before) do
        local new_binding = after[stop_id]
        if new_binding and new_binding.y1 ~= old_binding.y1 then return true end
    end
    return false
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
            recenter_indicator=copy_coord(
                df.global.game.main_interface.recenter_indicator_m),
            follow_unit=df.global.plotinfo.follow_unit,
            follow_item=df.global.plotinfo.follow_item,
            minimap_update=df.global.game.minimap.update,
            minimap_mustmake=df.global.game.minimap.mustmake,
        }
        local saved_unit_card = snapshot_unit_card()
        local screen
        local hauling
        local root
        local registered
        local overlay_plugin
        local old_focus_provider
        local old_map_overlay_renderer
        local map_render_calls = {}
        local native_focus
        local ok, failure = xpcall(function()
            -- Normalize the native fortress UI before opening the Hauling menu
            -- through the same input binding available to a player.
            screen = assert(dfhack.gui.getDFViewscreen(true),
                'prepared save must have a fortress viewscreen')
            saved.hauling_was_open =
                dfhack.gui.matchFocusString('dwarfmode/Hauling', screen)
            if saved.hauling_was_open then
                saved.scroll_position =
                    assert(df.global.plotinfo.hauling).scroll_position
            end
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
            saved.scroll_position =
                saved.scroll_position or hauling.scroll_position
            native_focus = dfhack.gui.getFocusStrings(screen)
            assert.is_table(native_focus,
                'DFHack must expose the native focus-string list')
            assert.is_true(require('utils').linear_index(native_focus,
                'dwarfmode/Hauling') ~= nil,
                'native focus list does not contain dwarfmode/Hauling')

            -- Add a transparent one-cell interaction target to the production
            -- component instance. DwarfSpec can then own the exact pointer
            -- position without replacing dfhack.screen.getMousePos in the test.
            overlay_plugin = require('plugins.overlay')
            local prior_overlay_state = overlay_plugin.get_state()
            local prior_registered =
                prior_overlay_state.db[REGISTERED_WIDGET] and
                    prior_overlay_state.db[REGISTERED_WIDGET].widget
            saved.registered_was_present = prior_registered ~= nil
            saved.registered_selection_id = prior_registered and
                prior_registered.selection and
                prior_registered.selection:get_selected_route_id() or nil
            dfhack.run_command('dwarfui reload')
            local MinecartRouteMarkersOverlay = reqscript(
                'dwarfui-minecart-route-markers').MinecartRouteMarkersOverlay
            local AssetButton =
                reqscript('dwarfui/widgets/asset_button').AssetButton
            local overlay_state = overlay_plugin.get_state()
            local registered_entry = assert(overlay_state.db[REGISTERED_WIDGET],
                'production minecart-route overlay is not registered')
            assert.is_true(overlay_state.config[REGISTERED_WIDGET].enabled,
                'production minecart-route overlay is not enabled')
            registered = registered_entry.widget
            assert.is_true(registered.visible,
                'production minecart-route overlay is not visible')
            -- The native viewscreen exposes its new focus immediately, but
            -- DFHack publishes getCurFocus() on the following update. Wait for
            -- the exact production focus provider before sending overlay input.
            ds.await('production overlay observes native Hauling focus',
                function()
                    return registered.layout:is_supported_focus(
                        registered.focus_provider())
                end)
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

            -- Inspect the canonical registered overlay's real pooled widgets
            -- and the screen buffer generated from the vanilla interface asset.
            assert_rendered_stop_buttons(registered, hauling, AssetButton,
                'registered production overlay')

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

            -- Bind and inspect the same production AssetButton class through the
            -- mounted component boundary before activating a real native stop.
            local component_buttons = assert_rendered_stop_buttons(
                root, hauling, AssetButton, 'mounted production component',
                false)
            local initial_button
            for _, button in ipairs(component_buttons) do
                local descriptor = assert(button.action_descriptor)
                if root.layout:find_route_header_y(hauling,
                        descriptor.route_id, native_focus) then
                    initial_button = button
                    break
                end
            end
            assert.is_table(initial_button,
                'prepared save requires a visible stop with its route header')
            local initial_descriptor = assert(initial_button.action_descriptor)
            local initial_route = assert(
                hauling.view_routes[initial_descriptor.row_index])
            local initial_stop = assert(
                hauling.view_stops[initial_descriptor.row_index])
            local initial_stop_pos = copy_coord(initial_stop.pos)
            local initial_scroll = hauling.scroll_position
            local initial_route_id = initial_route.id
            local initial_stop_id = initial_stop.id

            -- DwarfSpec positions the real pointer on the center cell of the
            -- rendered 3-by-3 button, then feeds the click through the mounted
            -- production component instead of invoking its callback.
            df.global.enabler.mouse_focus = true
            df.global.enabler.tracking_on = 1
            move_pointer_to_cell(root, pointer_target, pointer_subject,
                initial_descriptor.bounds.x1 + 1,
                initial_descriptor.bounds.y1 + 1)
            ds.click(pointer_subject)
            assert_centered_and_highlighted(initial_stop_pos,
                'real recenter-button click')
            assert.is_true(dfhack.gui.matchFocusString('dwarfmode/Hauling',
                dfhack.gui.getDFViewscreen(true)),
                'recenter click closed the native Hauling menu')
            assert.equals(initial_scroll, hauling.scroll_position,
                'recenter click changed the native list scroll position')
            assert.equals(initial_route_id,
                root.selection:get_selected_route_id(),
                'recenter click did not select its owning hauling route')
            assert.equals(initial_route_id,
                hauling.view_routes[initial_descriptor.row_index].id,
                'recenter click changed the underlying native route row')
            assert.equals(initial_stop_id,
                hauling.view_stops[initial_descriptor.row_index].id,
                'recenter click changed the underlying native stop row')
            local zoom_indicator_y = assert(
                root.layout:find_route_header_y(hauling, initial_route_id,
                    native_focus),
                'zoom-selected hauling route header is not visible') + 1
            assert_rendered_text(root.layout:get_indicator_x(),
                zoom_indicator_y, string.char(16), COLOR_YELLOW,
                'zoom click renders its hauling-route selection indicator')

            -- Scroll the actual native list only after DwarfSpec moves the real
            -- pointer over its row area. Repeatedly render until one retained
            -- stop visibly moves and one occupied button row becomes associated
            -- with a different stop at a different world position.
            local before_bindings =
                snapshot_button_bindings(component_buttons)
            local previous_screen_rows = {}
            for _, button in ipairs(component_buttons) do
                local descriptor = assert(button.action_descriptor)
                local stop = assert(hauling.view_stops[descriptor.row_index])
                previous_screen_rows[descriptor.bounds.y1] = {
                    stop_id=descriptor.stop_id,
                    pos=copy_coord(stop.pos),
                }
            end
            local scroll_key = 'CONTEXT_SCROLL_DOWN'
            local moved_binding = false
            local rebound_button
            local rebound_previous
            local native_x, native_y = move_pointer_to_cell(
                root, pointer_target, pointer_subject,
                root.layout.bounds.x1 + 2,
                root.layout.first_row_top + 1)
            -- The native C++ list reads gps coordinates instead of DFHack's
            -- patched getMousePos function. Mirror DwarfSpec's resolved pointer
            -- cell into that native buffer while exercising native scrolling.
            gps.mouse_x, gps.mouse_y = native_x, native_y
            gps.precise_mouse_x = native_x * gps.tile_pixel_x + 1
            gps.precise_mouse_y = native_y * gps.tile_pixel_y + 1
            require('gui').simulateInput(screen, '_MOUSE_L')
            for attempt=1,16 do
                local before_scroll = hauling.scroll_position
                require('gui').simulateInput(screen, scroll_key)
                ds.wait_frames(1)
                if hauling.scroll_position == before_scroll and attempt == 1 then
                    scroll_key = 'CONTEXT_SCROLL_UP'
                    require('gui').simulateInput(screen, scroll_key)
                    ds.wait_frames(1)
                end
                if hauling.scroll_position ~= before_scroll then
                    root:refresh_stop_actions(hauling)
                    ds.wait_frames(1)
                    local current_buttons =
                        root.stop_action_pool:get_active_buttons()
                    local current_bindings =
                        snapshot_button_bindings(current_buttons)
                    moved_binding = moved_binding or
                        has_moved_binding(before_bindings, current_bindings)
                    before_bindings = current_bindings
                    for _, current_button in ipairs(current_buttons) do
                        local rebound_descriptor =
                            current_button.action_descriptor
                        local previous = rebound_descriptor and
                            previous_screen_rows[
                                rebound_descriptor.bounds.y1]
                        local rebound_stop = rebound_descriptor and
                            hauling.view_stops[
                                rebound_descriptor.row_index]
                        if previous and rebound_stop and
                                rebound_descriptor.stop_id ~=
                                    previous.stop_id and
                                not same_coord(previous.pos,
                                    rebound_stop.pos) then
                            rebound_button = current_button
                            rebound_previous = previous
                            break
                        end
                    end
                    if moved_binding and rebound_button then break end
                end
            end
            assert.is_true(hauling.scroll_position ~= initial_scroll,
                'native route list did not scroll with the pointer over it')
            assert.is_true(moved_binding,
                'native scrolling did not move retained visible stop buttons')
            assert.is_table(rebound_button,
                ('native scrolling did not rebind a pooled button to a new ' ..
                    'stop at an occupied screen row (before_scroll=%s ' ..
                    'after_scroll=%s)')
                    :format(tostring(initial_scroll),
                        tostring(hauling.scroll_position)))

            -- Activate the reused button at its new rendered location. Its
            -- current descriptor, highlight, and viewport must all target the
            -- newly visible stop rather than its previous binding.
            local rebound_descriptor =
                assert(rebound_button.action_descriptor)
            local rebound_stop = assert(
                hauling.view_stops[rebound_descriptor.row_index])
            local rebound_pos = copy_coord(rebound_stop.pos)
            assert.not_equals(rebound_previous.stop_id,
                rebound_descriptor.stop_id)
            assert.is_false(same_coord(rebound_previous.pos, rebound_pos),
                'prepared save requires scroll-rebound stops at different tiles')
            local rebound_scroll = hauling.scroll_position
            move_pointer_to_cell(root, pointer_target, pointer_subject,
                rebound_descriptor.bounds.x1 + 1,
                rebound_descriptor.bounds.y1 + 1)
            ds.click(pointer_subject)
            assert_centered_and_highlighted(rebound_pos,
                'scroll-rebound recenter-button click')
            assert.equals(rebound_descriptor.route_id,
                root.selection:get_selected_route_id(),
                'rebound zoom click did not select its current owning route')
            assert.equals(rebound_scroll, hauling.scroll_position,
                'rebound recenter click changed native list scroll position')
            assert.is_false(same_coord(rebound_previous.pos,
                df.global.game.main_interface.recenter_indicator_m),
                'rebound button still targeted its previous stop')
            assert.is_true(dfhack.gui.matchFocusString('dwarfmode/Hauling',
                dfhack.gui.getDFViewscreen(true)),
                'rebound recenter click closed the native Hauling menu')

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
                ds.await('native map viewport applies the off-z movement',
                    function()
                        return df.global.world.viewport.corner.z == off_z.z
                    end)
                map_render_calls = {}
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

        -- Unmount before restoring globals so DwarfSpec's own mount snapshot
        -- cannot overwrite the original pointer or viewport values below.
        if root then
            root:clear_selection()
            root.focus_provider = old_focus_provider
            root.map_overlay_renderer = old_map_overlay_renderer
            ds.unmount()
        end

        -- Restore native list, pointer, viewport, highlight, follow state, and
        -- minimap invalidation flags even when an assertion above fails.
        if hauling and saved.scroll_position then
            hauling.scroll_position = saved.scroll_position
        end
        gps.mouse_x, gps.mouse_y = saved.mouse_x, saved.mouse_y
        gps.precise_mouse_x, gps.precise_mouse_y = saved.precise_mouse_x,
            saved.precise_mouse_y
        df.global.window_x, df.global.window_y, df.global.window_z =
            saved.window_x, saved.window_y, saved.window_z
        local indicator =
            df.global.game.main_interface.recenter_indicator_m
        indicator.x, indicator.y, indicator.z =
            saved.recenter_indicator.x, saved.recenter_indicator.y,
            saved.recenter_indicator.z
        df.global.plotinfo.follow_unit = saved.follow_unit
        df.global.plotinfo.follow_item = saved.follow_item
        df.global.game.minimap.update = saved.minimap_update
        df.global.game.minimap.mustmake = saved.minimap_mustmake
        df.global.enabler.mouse_focus = saved.mouse_focus
        df.global.enabler.tracking_on = saved.tracking_on

        -- Close the menu opened by the test, then recreate the original native
        -- screen state when the player already had Hauling open beforehand.
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
        if saved.hauling_was_open and not saved_unit_card.open then
            native_screen = assert(dfhack.gui.getDFViewscreen(true))
            require('gui').simulateInput(native_screen, 'D_HAULING')
            ds.await('original native Hauling menu reopens', function()
                return dfhack.gui.matchFocusString('dwarfmode/Hauling',
                    dfhack.gui.getDFViewscreen(true))
            end)
            if hauling and saved.scroll_position then
                hauling.scroll_position = saved.scroll_position
            end
        end
        if overlay_plugin then
            local restored_state = overlay_plugin.get_state()
            local restored_entry = restored_state.db[REGISTERED_WIDGET]
            if restored_entry and restored_entry.widget.selection then
                restored_entry.widget.selection.selected_route_id =
                    saved.registered_selection_id
            end
        end
        df.global.game.minimap.update = saved.minimap_update
        df.global.game.minimap.mustmake = saved.minimap_mustmake

        -- Prove every manually owned state value is back to its original value.
        assert.equals(saved.mouse_x, gps.mouse_x,
            'cleanup retained a changed native pointer x')
        assert.equals(saved.mouse_y, gps.mouse_y,
            'cleanup retained a changed native pointer y')
        assert.equals(saved.precise_mouse_x, gps.precise_mouse_x,
            'cleanup retained a changed precise pointer x')
        assert.equals(saved.precise_mouse_y, gps.precise_mouse_y,
            'cleanup retained a changed precise pointer y')
        assert.equals(saved.window_x, df.global.window_x,
            'cleanup retained a changed viewport x')
        assert.equals(saved.window_y, df.global.window_y,
            'cleanup retained a changed viewport y')
        assert.equals(saved.window_z, df.global.window_z,
            'cleanup retained a changed viewport z-level')
        assert.same(saved.recenter_indicator, copy_coord(
            df.global.game.main_interface.recenter_indicator_m),
            'cleanup retained the native location highlight')
        assert.equals(saved.follow_unit, df.global.plotinfo.follow_unit,
            'cleanup retained a changed followed unit')
        assert.equals(saved.follow_item, df.global.plotinfo.follow_item,
            'cleanup retained a changed followed item')
        assert.equals(saved.minimap_update, df.global.game.minimap.update,
            'cleanup retained a changed minimap update flag')
        assert.equals(saved.minimap_mustmake, df.global.game.minimap.mustmake,
            'cleanup retained a changed minimap rebuild flag')
        assert.equals(saved.mouse_focus, df.global.enabler.mouse_focus,
            'cleanup retained changed native mouse focus')
        assert.equals(saved.tracking_on, df.global.enabler.tracking_on,
            'cleanup retained changed native pointer tracking')
        assert.equals(saved.scroll_position, hauling.scroll_position,
            'cleanup retained a changed native list scroll position')
        assert.equals(saved.hauling_was_open,
            dfhack.gui.matchFocusString('dwarfmode/Hauling',
                dfhack.gui.getDFViewscreen(true)),
            'cleanup did not restore the original Hauling screen state')
        if root then
            assert.is_nil(root.selection:get_selected_route_id(),
                'cleanup retained mounted route selection')
        end
        if overlay_plugin and saved.registered_was_present then
            local restored_entry =
                overlay_plugin.get_state().db[REGISTERED_WIDGET]
            assert.equals(saved.registered_selection_id,
                restored_entry.widget.selection:get_selected_route_id(),
                'cleanup retained changed registered route selection')
        end
        assert.is_true(ok, failure)
    end)
end)
