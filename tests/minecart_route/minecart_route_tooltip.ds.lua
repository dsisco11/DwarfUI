-- Focused native coverage for input-independent minecart zoom tooltip intent.

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

---Copies an array without retaining its source table.
---@param values any[]
---@return any[]
local function copy_array(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

---Captures focus, native viewscreen identity, and pause state.
---@param native_subject dwarfspec.Subject
---@return table snapshot
local function capture_environment(native_subject)
    return {
        focus=copy_array(native_subject:getFocusList()),
        current_viewscreen=dfhack.gui.getCurViewscreen(true),
        native_viewscreen=dfhack.gui.getDFViewscreen(true),
        paused=ds.isGamePaused(),
    }
end

---Asserts that tooltip activity has not changed game UI ownership.
---@param expected table
---@param native_subject dwarfspec.Subject
---@param label string
local function assert_environment(expected, native_subject, label)
    assert.same(expected.focus, native_subject:getFocusList(),
        label .. ' changed the DwarfSpec focus strings')
    assert.is_equal(expected.current_viewscreen,
        dfhack.gui.getCurViewscreen(true),
        label .. ' changed the current viewscreen')
    assert.is_equal(expected.native_viewscreen,
        dfhack.gui.getDFViewscreen(true),
        label .. ' changed the native viewscreen')
    assert.equals(expected.paused, ds.isGamePaused(),
        label .. ' changed pause state')
end

---Asserts that diagnostics expose input state without presentation ownership.
---@param state table
local function assert_input_only_diagnostics(state)
    assert.is_nil(state.screen)
    assert.is_nil(state.overlay)
    assert.is_nil(state.renderer)
    assert.is_nil(state.renderer_count)
    assert.is_nil(state.input_owner)
    assert.is_nil(state.input_handler)
    assert.is_nil(state.viewscreen)
    assert.is_number(state.poller_module_generation)
    assert.is_number(state.poller_generation)
    assert.is_number(state.sample_sequence)
    assert.is_true(state.poller_running)
    assert.is_true(state.poller_scheduled)
    assert.is_true(state.poller_current)
end

---Resolves the current registered production rail controls.
---@return table controls
local function resolve_controls()
    local source = {
        source='overlay',
        overlay=REGISTERED_WIDGET,
    }
    local controls
    ds.await('registered minecart controls observe Hauling', function()
        local rail_ok, rail = pcall(ds.get, 'stop_action_rail', source)
        local surface_ok, surface = pcall(
            ds.get, 'stop_action_rail/surface', source)
        local zoom_ok, zoom = pcall(
            ds.get, 'stop_action_rail/surface/recenter', source)
        if not rail_ok or not surface_ok or not zoom_ok then return false end
        local overlay = rail:raw().parent_view
        if not overlay or not overlay.layout.bounds then return false end
        controls = {
            rail_subject=rail,
            surface_subject=surface,
            zoom_subject=zoom,
            overlay=overlay,
            action=zoom:raw(),
        }
        return true
    end)
    return controls
end

---Moves through the native stop row to reveal the production action rail.
---@param hauling df.hauling_handlerst
---@param controls table
---@return {x: integer, y: integer}
local function reveal_action(hauling, controls)
    local stop = find_visible_stop(hauling, controls.overlay.layout)
    ds.move_pointer(stop.x, stop.y)
    ds.redraw()
    ds.await('stop action rail is visible', function()
        return controls.surface_subject:inspect().visible
    end)
    return stop
end

---Moves onto the production zoom action and awaits its static intent.
---@param controls table
---@return integer x
---@return integer y
---@return table diagnostics
local function select_zoom_action(controls)
    local x, y = ds.move_pointer(controls.zoom_subject)
    ds.redraw()
    ds.await('singleton publishes the zoom action tooltip intent', function()
        local state = ds.tooltip_state()
        return state.target == controls.action and state.intent and
            state.intent.text == 'Zoom to this stop'
    end)
    return x, y, ds.tooltip_state()
end

describe('native minecart zoom tooltip polling', function()
    it('tracks the production action independently of input and UI ownership',
            function()
        local native_subject
        local controls
        local modified_action
        local initially_open
        local initial_scroll
        local initial_pause
        local initial_pointer_x
        local initial_pointer_y
        local saved_action_fields
        local registration_to_restore

        ---Restores test-owned method and tooltip overrides on the live action.
        local function restore_action()
            if not modified_action or not saved_action_fields then return end
            modified_action.tooltip = saved_action_fields.tooltip
            modified_action.on_pointer_update =
                saved_action_fields.on_pointer_update
            modified_action.on_pointer_leave =
                saved_action_fields.on_pointer_leave
            modified_action.onInput = saved_action_fields.onInput
            modified_action = nil
            saved_action_fields = nil
        end

        local ok, failure = xpcall(function()
            native_subject = ds.mountNativeScreen()
            initial_pause = ds.isGamePaused()
            initial_pointer_x, initial_pointer_y =
                dfhack.screen.getMousePos()
            initially_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_open then
                ds.input('LEAVESCREEN')
                ds.await('pre-existing Hauling menu closes', function()
                    return ds.hasFocus('dwarfmode/Default')
                end)
            end

            ds.input('D_HAULING')
            ds.await('native Hauling menu opens', function()
                return ds.hasFocus('dwarfmode/Hauling')
            end)

            local hauling = assert(df.global.plotinfo.hauling,
                'native Hauling state is unavailable')
            initial_scroll = hauling.scroll_position
            controls = resolve_controls()
            local stop = reveal_action(hauling, controls)
            local action = controls.action
            local tooltip = reqscript('dwarfui/tooltip')
            local environment = capture_environment(native_subject)

            -- The production overlay already registered this button. Cycle
            -- that registration through the public API to prove registration
            -- itself owns no focus, viewscreen, pause, or input state.
            assert.is_true(tooltip.unregister(action))
            registration_to_restore = action
            assert_environment(environment, native_subject,
                'tooltip unregistration')
            assert.is_true(tooltip.register(action))
            registration_to_restore = nil
            assert_environment(environment, native_subject,
                'tooltip registration')

            local zoom_x, zoom_y, state = select_zoom_action(controls)
            assert.is_equal(action, state.target)
            assert.equals('Zoom to this stop', state.intent.text)
            assert.equals(zoom_x, state.intent.anchor_x)
            assert.equals(zoom_y, state.intent.anchor_y)
            assert.equals('screen-cells', state.intent.coordinate_space)
            assert_input_only_diagnostics(state)
            assert_environment(environment, native_subject,
                'initial intent publication')

            modified_action = action
            saved_action_fields = {
                tooltip=action.tooltip,
                on_pointer_update=rawget(action, 'on_pointer_update'),
                on_pointer_leave=rawget(action, 'on_pointer_leave'),
                onInput=rawget(action, 'onInput'),
            }
            local inherited_update = action.on_pointer_update
            local inherited_leave = action.on_pointer_leave
            local inherited_input = action.onInput
            local update_count = 0
            local leave_count = 0
            local consumed_input_count = 0
            local latest_dynamic_text

            ---Updates dynamic tooltip text before the service snapshots it.
            ---@param self gui.View
            ---@param x integer
            ---@param y integer
            action.on_pointer_update = function(self, x, y)
                if inherited_update then inherited_update(self, x, y) end
                update_count = update_count + 1
                latest_dynamic_text =
                    ('Zoom to this stop at %d,%d'):format(x, y)
                self.tooltip = latest_dynamic_text
            end

            ---Records the polling path's pointer-leave transition.
            ---@param self gui.View
            action.on_pointer_leave = function(self)
                leave_count = leave_count + 1
                if inherited_leave then inherited_leave(self) end
            end

            ---Consumes a left click in the production widget dispatch path.
            ---@param self gui.View
            ---@param keys table
            ---@return boolean
            action.onInput = function(self, keys)
                if keys and keys._MOUSE_L and self:getMousePos() then
                    consumed_input_count = consumed_input_count + 1
                    return true
                end
                return inherited_input and inherited_input(self, keys) or false
            end

            local first_x, first_y =
                ds.move_pointer(controls.zoom_subject, 'top_left')
            ds.await('dynamic tooltip snapshots the first local position',
                function()
                    local current = ds.tooltip_state()
                    return current.target == action and current.intent and
                        current.intent.text == latest_dynamic_text and
                        current.intent.anchor_x == first_x and
                        current.intent.anchor_y == first_y
                end)
            local first_dynamic_text = latest_dynamic_text
            local second_x, second_y =
                ds.move_pointer(controls.zoom_subject, 'bottom_right')
            ds.await('dynamic tooltip snapshots the changed local position',
                function()
                    local current = ds.tooltip_state()
                    return latest_dynamic_text ~= first_dynamic_text and
                        current.target == action and current.intent and
                        current.intent.text == latest_dynamic_text and
                        current.intent.anchor_x == second_x and
                        current.intent.anchor_y == second_y
                end)

            state = ds.tooltip_state()
            local sequence_before_input = state.sample_sequence
            local revision_before_input = state.revision
            local updates_before_input = update_count
            ds.mouseInput(ds.EMouseButton.LEFT)
            assert.is_true(consumed_input_count > 0,
                'production action did not consume the routed mouse input')
            ds.await('polling continues after consumed widget input',
                function()
                    local current = ds.tooltip_state()
                    return current.sample_sequence > sequence_before_input and
                        current.revision > revision_before_input and
                        update_count > updates_before_input and
                        current.target == action and current.intent and
                        current.intent.text == latest_dynamic_text
                end)
            assert_environment(environment, native_subject,
                'consumed input and subsequent polling')

            ds.move_pointer(stop.x, stop.y)
            ds.await('moving off clears intent without synthetic input',
                function()
                    local current = ds.tooltip_state()
                    return leave_count == 1 and current.target == nil and
                        current.intent == nil
                end)
            assert_environment(environment, native_subject,
                'pointer-leave intent clearing')
            restore_action()

            -- Re-select the static production tooltip before reloading so the
            -- registration is live during the generation handoff.
            select_zoom_action(controls)
            local before_reload = ds.tooltip_state()
            local old_module_generation =
                before_reload.poller_module_generation
            local old_service_generation = before_reload.generation
            dfhack.run_command('dwarfui', 'reload')

            ds.await('one new poller generation resumes after reload',
                function()
                    local current = ds.tooltip_state()
                    return current.poller_module_generation ==
                            old_module_generation + 1 and
                        current.generation == old_service_generation + 1 and
                        current.poller_current and current.poller_running and
                        current.poller_scheduled and
                        current.sample_sequence > 0
                end)
            local after_reload = ds.tooltip_state()
            assert_input_only_diagnostics(after_reload)
            assert_environment(environment, native_subject,
                'dwarfui reload')

            controls = resolve_controls()
            stop = reveal_action(hauling, controls)
            select_zoom_action(controls)
            local sequence_before_frames =
                ds.tooltip_state().sample_sequence
            ds.wait_frames(3)
            local sequence_after_frames =
                ds.tooltip_state().sample_sequence
            assert.equals(3,
                sequence_after_frames - sequence_before_frames,
                'poller did not produce exactly one sample per frame')

            local registration_count =
                ds.tooltip_state().registration_count
            ds.input('LEAVESCREEN')
            ds.await('Hauling close clears an ineligible target', function()
                local current = ds.tooltip_state()
                return ds.hasFocus('dwarfmode/Default') and
                    current.target == nil and current.intent == nil and
                    current.poller_running and current.poller_scheduled
            end)

            ds.input('D_HAULING')
            ds.await('Hauling menu reopens after eligibility loss', function()
                return ds.hasFocus('dwarfmode/Hauling')
            end)
            controls = resolve_controls()
            stop = reveal_action(hauling, controls)
            select_zoom_action(controls)
            state = ds.tooltip_state()
            assert.equals(registration_count, state.registration_count,
                'Hauling reopen required tooltip re-registration')
            assert_input_only_diagnostics(state)
        end, debug.traceback)

        local cleanup_failures = {}

        ---Runs one cleanup step without preventing later restoration.
        ---@param label string
        ---@param callback function
        local function cleanup_step(label, callback)
            local step_ok, step_failure =
                xpcall(callback, debug.traceback)
            if not step_ok then
                table.insert(cleanup_failures,
                    label .. ': ' .. tostring(step_failure))
            end
        end

        cleanup_step('restore action overrides', restore_action)
        cleanup_step('restore interrupted registration', function()
            if registration_to_restore then
                reqscript('dwarfui/tooltip').register(
                    registration_to_restore)
                registration_to_restore = nil
            end
        end)
        cleanup_step('clear overlay state', function()
            if controls and controls.overlay then
                controls.overlay:clear_overlay_state()
            end
        end)
        cleanup_step('restore pointer position', function()
            if native_subject and initial_pointer_x ~= nil and
                    initial_pointer_y ~= nil and initial_pointer_x >= 0 and
                    initial_pointer_y >= 0 then
                ds.move_pointer(initial_pointer_x, initial_pointer_y)
            end
        end)
        cleanup_step('restore native menu state', function()
            if not native_subject then return end
            local is_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_open and not is_open then
                ds.input('D_HAULING')
                ds.await('original Hauling menu reopens', function()
                    return ds.hasFocus('dwarfmode/Hauling')
                end)
            elseif not initially_open and is_open then
                ds.input('LEAVESCREEN')
                ds.await('test Hauling menu closes', function()
                    return ds.hasFocus('dwarfmode/Default')
                end)
            end
        end)
        cleanup_step('restore Hauling scroll position', function()
            if initial_scroll ~= nil and df.global.plotinfo.hauling then
                df.global.plotinfo.hauling.scroll_position = initial_scroll
            end
        end)
        cleanup_step('restore pause state', function()
            if native_subject and initial_pause ~= nil and
                    ds.isGamePaused() ~= initial_pause then
                ds.setGamePaused(initial_pause)
            end
        end)
        cleanup_step('unmount native screen', function()
            if native_subject then
                ds.unmount()
                native_subject = nil
            end
        end)

        if #cleanup_failures > 0 then
            local cleanup_message =
                'cleanup failures: ' .. table.concat(cleanup_failures, '; ')
            failure = failure and
                (tostring(failure) .. '\n' .. cleanup_message) or
                cleanup_message
            ok = false
        end
        assert.is_true(ok, failure)
    end)
end)
