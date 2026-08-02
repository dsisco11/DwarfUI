-- Focused visible minecart route tooltip coverage.

local MinecartRouteFixture = require('tests.minecart_route.support.route_fixture')
local REGISTERED_WIDGET = 'dwarfui-minecart-route-markers.minecart_route_markers'

---Returns one fully visible native minecart stop row.
---@param hauling df.hauling_handlerst
---@param layout dwarfui.MinecartRouteMenuLayout
---@return {x: integer, y: integer}
local function find_visible_stop(hauling, layout)
    local first = hauling.scroll_position or 0
    local visible_count = math.floor((layout.bounds.y2 - layout.first_row_top + 1) / layout.row_height)
    for visible=0,visible_count - 1 do
        local index = first + visible
        if hauling.view_routes[index] and hauling.view_stops[index] and hauling.view_stops[index].pos then
            return {x=layout.bounds.x1 + 2, y=layout.first_row_top + visible * layout.row_height + 1}
        end
    end
    error('prepared save requires one fully visible minecart stop')
end

---Resolves the registered production rail controls.
---@return table controls
local function resolve_controls()
    local source = {source='overlay', overlay=REGISTERED_WIDGET}
    local controls
    ds.await('registered minecart controls observe Hauling', function()
        local rail_ok, rail = pcall(ds.get, 'stop_action_rail', source)
        local surface_ok, surface = pcall(ds.get, 'stop_action_rail/surface', source)
        local zoom_ok, zoom = pcall(ds.get, 'stop_action_rail/surface/recenter', source)
        if not rail_ok or not surface_ok or not zoom_ok then return false end
        local route_overlay = rail:raw().parent_view
        if not route_overlay or not route_overlay.layout.bounds then return false end
        controls = {surface=surface, zoom=zoom, overlay=route_overlay}
        return true
    end)
    return controls
end

---Reveals the stop action rail for one native row.
---@param hauling df.hauling_handlerst
---@param controls table
---@return {x: integer, y: integer}
local function reveal_action(hauling, controls)
    local stop = find_visible_stop(hauling, controls.overlay.layout)
    ds.move_pointer(stop.x, stop.y)
    ds.redraw()
    ds.await('stop action rail is visible', function()
        return controls.surface:inspect().visible
    end)
    return stop
end

---Selects the visible zoom action and waits for its public tooltip intent.
---@param controls table
---@return integer x
---@return integer y
local function select_zoom_action(controls)
    local x, y = ds.move_pointer(controls.zoom)
    ds.redraw()
    ds.await('zoom action tooltip is visible', function()
        local state = ds.tooltip_state()
        return state.intent and state.intent.text == 'Zoom to this stop'
    end)
    return x, y
end

describe('native minecart route tooltip', function()
    it('shows the route zoom tooltip, clears it when ineligible, and restores it after overlay recreation', function()
        local native_subject
        local controls
        local route_fixture
        local initially_open
        local initial_scroll
        local ok, failure = xpcall(function()
            native_subject = ds.mountNativeScreen()
            initially_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_open then
                ds.input('LEAVESCREEN')
                ds.await('pre-existing Hauling menu closes', function() return ds.hasFocus('dwarfmode/Default') end)
            end
            route_fixture = MinecartRouteFixture.create()
            ds.input('D_HAULING')
            ds.await('native Hauling menu opens', function() return ds.hasFocus('dwarfmode/Hauling') end)
            local hauling = assert(df.global.plotinfo.hauling, 'native Hauling state is unavailable')
            initial_scroll = hauling.scroll_position
            controls = resolve_controls()
            local stop = reveal_action(hauling, controls)
            local zoom_x, zoom_y = select_zoom_action(controls)
            local state = ds.tooltip_state()
            assert.equals(zoom_x, state.intent.anchor_x)
            assert.equals(zoom_y, state.intent.anchor_y)
            assert.equals('screen-cells', state.intent.coordinate_space)
            ds.move_pointer(stop.x, stop.y)
            ds.await('leaving the action clears its tooltip', function() return ds.tooltip_state().intent == nil end)
            ds.input('LEAVESCREEN')
            ds.await('Hauling close clears the route action', function() return ds.hasFocus('dwarfmode/Default') and ds.tooltip_state().intent == nil end)
            ds.input('D_HAULING')
            ds.await('native Hauling menu reopens', function() return ds.hasFocus('dwarfmode/Hauling') end)
            controls = resolve_controls()
            reveal_action(hauling, controls)
            select_zoom_action(controls)
            dfhack.run_command('dwarfui', 'reload')
            controls = resolve_controls()
            reveal_action(hauling, controls)
            select_zoom_action(controls)
            assert.equals('Zoom to this stop', ds.tooltip_state().intent.text)
        end, debug.traceback)
        local cleanup_failures = {}
        ---Runs one cleanup step without preventing later cleanup.
        ---@param label string
        ---@param callback function
        local function cleanup_step(label, callback)
            local step_ok, step_failure = xpcall(callback, debug.traceback)
            if not step_ok then table.insert(cleanup_failures, label .. ': ' .. tostring(step_failure)) end
        end
        cleanup_step('clear production overlay state', function() if controls and controls.overlay then controls.overlay:clear_overlay_state() end end)
        cleanup_step('restore native menu state', function()
            if not native_subject then return end
            local is_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_open and not is_open then
                ds.input('D_HAULING')
                ds.await('original Hauling menu reopens', function() return ds.hasFocus('dwarfmode/Hauling') end)
            elseif not initially_open and is_open then
                ds.input('LEAVESCREEN')
                ds.await('test Hauling menu closes', function() return ds.hasFocus('dwarfmode/Default') end)
            end
        end)
        cleanup_step('remove disposable routes', function() MinecartRouteFixture.destroy(route_fixture) end)
        cleanup_step('restore Hauling scroll position', function()
            if initial_scroll ~= nil and df.global.plotinfo.hauling then df.global.plotinfo.hauling.scroll_position = initial_scroll end
        end)
        cleanup_step('release native screen observation', function() if native_subject then ds.unmount() end end)
        if #cleanup_failures > 0 then
            failure = (failure and tostring(failure) .. '\n' or '') .. 'cleanup failures: ' .. table.concat(cleanup_failures, '; ')
            ok = false
        end
        assert.is_true(ok, failure)
    end)
end)
