-- Native route-stop context-menu acceptance coverage.

local MinecartRouteFixture = require(
    'tests.minecart_route.support.route_fixture')
local prompt_service = reqscript('dwarfuicore/user_prompt/service').service
local context_menu_service = reqscript('dwarfuicore/context_menu/service').service
local DetectionKind = reqscript('dwarfuicore/context_menu/target_detector').
    ContextMenuDetectionKind
local InputTransport = reqscript('dwarfuicore/context_menu/input_hook').
    ContextMenuInputTransport
local map_projection = reqscript('dwarfuicore/map_projection')

local REGISTERED_WIDGET =
    'dwarfui-minecart-route-markers.minecart_route_markers'

---Returns one visible native route stop and its rendered list coordinates.
---@param hauling df.hauling_handlerst
---@param layout dwarfui.MinecartRouteMenuLayout
---@return {route: df.hauling_route, stop: df.hauling_stop, x: integer, y: integer}
local function find_visible_stop(hauling, layout)
    local first = hauling.scroll_position or 0
    local visible_count = math.floor((layout.bounds.y2 - layout.first_row_top +
        1) / layout.row_height)
    for visible=0,visible_count - 1 do
        local header_index = first + visible
        local route = hauling.view_routes[header_index]
        if route and not hauling.view_stops[header_index] then
            for next_visible=visible + 1,visible_count - 1 do
                local stop_index = first + next_visible
                local stop = hauling.view_stops[stop_index]
                if hauling.view_routes[stop_index] ~= route then break end
                if stop and stop.pos then
                    return {
                        route=route,
                        stop=stop,
                        x=layout.bounds.x1 + 2,
                        y=layout.first_row_top +
                            next_visible * layout.row_height + 1,
                    }
                end
            end
        end
    end
    error('prepared save requires a visible route stop')
end

---Copies one native coordinate without retaining the backing userdata.
---@param pos {x: integer, y: integer, z: integer}
---@return {x: integer, y: integer, z: integer}
local function copy_coord(pos)
    return {x=pos.x, y=pos.y, z=pos.z}
end

---Returns whether two world coordinates are equal.
---@param left {x: integer, y: integer, z: integer}
---@param right {x: integer, y: integer, z: integer}
---@return boolean
local function same_coord(left, right)
    return left.x == right.x and left.y == right.y and left.z == right.z
end

---Returns whether a complete string appears in a captured screen row.
---@param capture dwarfspec.ScreenCapture
---@param text string
---@return boolean
local function capture_contains_text(capture, text)
    for _, cells in ipairs(capture.cells) do
        local chars = {}
        for _, cell in ipairs(cells) do
            chars[#chars + 1] = string.char(cell.ch or 32)
        end
        if table.concat(chars):find(text, 1, true) then return true end
    end
    return false
end

---Captures the complete current DFHack screen.
---@param name string
---@return dwarfspec.ScreenCapture
local function capture_screen(name)
    local width, height = dfhack.screen.getWindowSize()
    return ds.capture_screen(name, {max_width=width, max_height=height})
end

---Moves to a visible map tile different from `position` and returns it.
---@param position {x: integer, y: integer, z: integer}
---@return {x: integer, y: integer, z: integer}
local function visible_relocation_tile(position)
    local search = copy_coord(position)
    for attempt=0,16 do
        search.x = position.x + attempt + 1
        search.y = position.y + attempt + 1
        ds.move_pointer(search, ds.EPointerSpace.WORLD_TILE, {recenter=false})
        ds.redraw()
        local projected = dfhack.gui.getMousePos(true)
        if projected ~= nil then
            local candidate = copy_coord(projected)
            if not same_coord(candidate, position) then
                return candidate
            end
        end
    end
    error('no visible replacement tile was found for relocation')
end

---Opens the route-stop context menu at current stop and validates prompt entry text.
---@param target {route: df.hauling_route, stop: df.hauling_stop, x: integer, y: integer}
---@param overlay table
local function open_route_stop_context_menu(target, overlay)
    local overlay_handle = overlay and
        overlay.map_context_menu_handles[target.stop.id]
    assert.is_not_nil(overlay_handle,
        'route-stop context-menu handle is unavailable')
    local stop_pos = copy_coord(target.stop.pos)
    ds.move_pointer(stop_pos, ds.EPointerSpace.WORLD_TILE, {recenter=false})
    local sample = context_menu_service._sampler:capture()
    assert.same(stop_pos, {
        x=sample.map_x,
        y=sample.map_y,
        z=sample.map_z,
    }, 'marker pointer did not resolve the native stop tile')
    local detection = context_menu_service._detector:detect(sample)
    assert.equals(DetectionKind.TARGET, detection.kind,
        'registered route-stop marker did not win context-menu arbitration')
    assert.is_equal(overlay_handle, detection.candidate.source,
        'route-stop marker did not supply the detected context target')
    assert.is_true(context_menu_service:handle_opening_input(
        {_MOUSE_R=true}, InputTransport.NATIVE,
        dfhack.gui.getCurViewscreen()),
        'native context-menu opening transition rejected the marker')
    local diagnostics = context_menu_service:get_diagnostics()
    assert.is_true(diagnostics.started and diagnostics.hook.native_tracked
        and diagnostics.hook.handler_installed,
        'route-stop registration did not install native context input')

    ds.redraw()
    assert.is_true(context_menu_service:is_open())
    ds.await('route-stop context menu opens', function()
        return ds.hasFocus('dfhack/lua/dwarfuicore/context-menu')
    end)
    local screen = context_menu_service._state.presentation.screen
    assert.is_true(screen:source_root_is_presented(
        screen.session:get_source_root()),
        'route-stop overlay source is not presented to the context menu')

    local menu_capture = capture_screen('route_stop_context_menu')
    local stop_title = 'Route Stop: ' ..
        (target.stop.name ~= '' and target.stop.name or '(unnamed)')
    assert.is_true(capture_contains_text(menu_capture, stop_title),
        'route-stop context menu did not render the route-stop title')
    assert.is_true(capture_contains_text(
        menu_capture, 'Relocate / Change location'),
        'route-stop context menu did not render the relocation action')
end

describe('native route-stop context menu', function()
    it('opens relocation prompt, updates on select, and cancels without mutation',
            function()
        local native_subject
        local route_fixture
        local overlay
        local overlay_source = {source='overlay', overlay=REGISTERED_WIDGET}
        local initially_open
        local initial_scroll
        local hauling_opened = false
        local ok, failure = xpcall(function()
            native_subject = ds.mountNativeScreen()
            initially_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_open then
                ds.input('LEAVESCREEN')
                ds.await('pre-existing Hauling menu closes', function()
                    return ds.hasFocus('dwarfmode/Default')
                end)
            end

            route_fixture = MinecartRouteFixture.create()
            ds.input('D_HAULING')
            ds.await('native Hauling menu opens', function()
                return ds.hasFocus('dwarfmode/Hauling')
            end)
            hauling_opened = true
            local hauling = assert(df.global.plotinfo.hauling,
                'native Hauling state is unavailable')
            initial_scroll = hauling.scroll_position
            local rail_subject
            ds.await('registered route overlay observes Hauling', function()
                local rail_ok, rail = pcall(ds.get, 'stop_action_rail',
                    overlay_source)
                if not rail_ok then return false end
                overlay = rail:raw().parent_view
                rail_subject = rail
                return overlay and overlay.layout.bounds ~= nil
            end)
            assert.is_not_nil(rail_subject)

            local target = find_visible_stop(hauling, overlay.layout)
            ds.move_pointer(target.x, target.y)
            local surface_subject = ds.get('stop_action_rail/surface',
                overlay_source)
            ds.await('route-stop action rail renders', function()
                return surface_subject:inspect().visible
            end)
            ds.mouseInput(ds.EMouseButton.LEFT)
            local zoom_subject = ds.get(
                'stop_action_rail/surface/recenter', overlay_source)
            zoom_subject:click()
            ds.redraw()
            local projection = map_projection.project_visible(target.stop.pos)
            assert.is_true(df.global.window_z == target.stop.pos.z and
                    projection ~= nil,
                ('route-stop marker pos=%d,%d,%d window=%d,%d,%d projection=%s')
                    :format(target.stop.pos.x, target.stop.pos.y,
                        target.stop.pos.z, df.global.window_x,
                        df.global.window_y, df.global.window_z,
                        projection and ('%d,%d,%d'):format(
                            projection.x, projection.y, projection.z) or 'nil'))
            ds.await('selected route registers its same-z stop context menu',
                function()
                    return overlay.map_context_menu_handles[target.stop.id] ~= nil
            end)
            assert.is_not_nil(map_projection.project_visible(target.stop.pos),
                'route-stop map position is no longer visible to the context menu')
            ds.redraw()
            open_route_stop_context_menu(target, overlay)

            ds.input('SELECT')
            ds.await('relocation prompt opens', function()
                return prompt_service:has_active_prompt()
            end)
            ds.redraw()
            local original_pos = copy_coord(target.stop.pos)
            local relocated_pos = visible_relocation_tile(target.stop.pos)
            ds.mouseInput(ds.EMouseButton.LEFT)
            ds.await('relocation prompt closes after selection', function()
                return not prompt_service:has_active_prompt()
            end)
            ds.await('relocation prompt returns to hauling', function()
                return ds.hasFocus('dwarfmode/Hauling')
            end)
            assert.is_false(same_coord(target.stop.pos, original_pos),
                'route stop position was not updated')
            assert.is_true(same_coord(relocated_pos, target.stop.pos),
                'route stop position was not set to selected relocation tile')

            open_route_stop_context_menu(target, overlay)
            local canceled_pos = copy_coord(target.stop.pos)
            ds.input('SELECT')
            ds.await('relocation cancel prompt opens', function()
                return prompt_service:has_active_prompt()
            end)
            ds.mouseInput(ds.EMouseButton.RIGHT)
            ds.await('relocation prompt cancels', function()
                return not prompt_service:has_active_prompt()
            end)
            ds.await('relocation cancel returns to hauling', function()
                return ds.hasFocus('dwarfmode/Hauling')
            end)
            assert.is_true(same_coord(canceled_pos, target.stop.pos),
                'route stop position changed during cancel flow')
        end, debug.traceback)

        if native_subject and hauling_opened and
                not ds.hasFocus('dwarfmode/Hauling') then
            ds.input('LEAVESCREEN')
            ds.await('test screens close to Hauling', function()
                return ds.hasFocus('dwarfmode/Hauling')
            end)
        end
        if route_fixture and initial_scroll ~= nil then
            route_fixture.hauling.scroll_position = initial_scroll
        end
        MinecartRouteFixture.destroy(route_fixture)
        if prompt_service and prompt_service:has_active_prompt() then
            ds.input('LEAVESCREEN')
            ds.await('relocation prompt closes on cleanup', function()
                return not prompt_service:has_active_prompt()
            end)
        end
        if native_subject and not initially_open and ds.hasFocus('dwarfmode/Hauling') then
            ds.input('LEAVESCREEN')
            ds.await('test Hauling menu closes', function()
                return ds.hasFocus('dwarfmode/Default')
            end)
        elseif native_subject and initially_open and not ds.hasFocus('dwarfmode/Hauling') then
            ds.input('D_HAULING')
            ds.await('original Hauling menu reopens', function()
                return ds.hasFocus('dwarfmode/Hauling')
            end)
        end
        assert.is_true(ok, failure)
    end)
end)
