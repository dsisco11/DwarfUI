-- Focused native coverage for input-independent minecart zoom tooltip intent.

local gui = require('gui')
local overlay = require('plugins.overlay')

local REGISTERED_WIDGET =
    'dwarfui-minecart-route-markers.minecart_route_markers'
local RENDER_OVERLAY_SOURCE =
    'tests/tooltip/support/tooltip_render_seam_overlays.lua'
local RENDER_PROBE_SLOT = 'tooltip_final_render_probe'

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
    assert.is_table(state.presenter)
    assert.is_number(state.presenter.generation)
    assert.is_boolean(state.presenter.active)
    assert.is_nil(state.presenter.selected_owner)
    assert.is_boolean(state.presenter.selected_owner_present)
    assert.is_table(state.render_hook)
    assert.is_number(state.render_hook.generation)
    assert.is_boolean(state.render_hook.presenter_installed)
    assert.is_nil(state.render_hook.selected_owner)
    assert.is_boolean(state.render_hook.selected_owner_present)
    assert.is_table(state.render_hook.overlay)
    assert.is_nil(state.render_hook.overlay.owner)
    assert.is_boolean(state.render_hook.overlay.owner_present)
    assert.is_table(state.render_hook.screens)
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

---Returns the first rendered text cell for one tooltip intent.
---@param intent table
---@return integer x
---@return integer y
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

---Returns the display character currently occupying one screen cell.
---@param x integer
---@param y integer
---@return string|nil
local function read_character(x, y)
    local pen = dfhack.screen.readTile(x, y)
    if not pen or pen.ch == nil then return nil end
    if type(pen.ch) == 'number' then return string.char(pen.ch) end
    return pen.ch
end

---Finds one staged overlay widget by its local registration suffix.
---@param staged table
---@param local_name string
---@return table
local function staged_overlay_widget(staged, local_name)
    local suffix = '.' .. local_name
    for _, name in ipairs(staged.registered_names) do
        if name:sub(-#suffix) == suffix then
            local entry = assert(overlay.get_state().db[name],
                'staged overlay entry is unavailable: ' .. name)
            return assert(entry.widget,
                'staged overlay widget is unavailable: ' .. name)
        end
    end
    error('staged overlay name is unavailable: ' .. local_name)
end

---Returns one staged overlay's current render count.
---@param staged table
---@param local_name string
---@return integer
local function staged_overlay_render_count(staged, local_name)
    return staged_overlay_widget(staged, local_name).render_count or 0
end

---Asserts one coherent active native-overlay tooltip render generation.
---@param state table
---@param minimum_rendered_revision integer
---@param expected_outermost boolean
local function assert_native_render_diagnostics(
        state, minimum_rendered_revision, expected_outermost)
    local transport =
        reqscript('dwarfui/tooltip_render_hook').TooltipRenderTransport
    assert.is_true(state.presenter.active)
    assert.is_true(state.presenter.supported_surface)
    assert.equals(transport.OVERLAY,
        state.presenter.selected_transport)
    assert.equals(state.intent.revision,
        state.presenter.current_intent_revision)
    assert.is_true(state.presenter.last_rendered_revision >=
        minimum_rendered_revision)
    assert.is_true(state.presenter.last_rendered_revision <=
        state.intent.revision)
    assert.is_true(state.render_hook.presenter_installed)
    assert.equals(state.presenter.generation,
        state.render_hook.generation)
    assert.equals(transport.OVERLAY,
        state.render_hook.selected_transport)
    assert.equals(state.intent.revision,
        state.render_hook.current_intent_revision)
    assert.equals(state.presenter.last_rendered_revision,
        state.render_hook.last_rendered_revision)
    assert.equals(transport.OVERLAY,
        state.render_hook.last_transport)
    assert.is_true(state.render_hook.overlay.installed)
    assert.equals(expected_outermost,
        state.render_hook.overlay.outermost)
    assert.equals(0, state.render_hook.screen_hook_count)
end

---Installs a reversible foreign wrapper outside the active tooltip hook.
---@return table record
local function install_foreign_overlay_wrapper()
    local hook = reqscript('dwarfui/tooltip_render_hook')
    local active_record = assert(hook.manager._state.overlay_hook,
        'active tooltip overlay hook is unavailable')
    local current_export = overlay.render_viewscreen_widgets
    local record = {
        predecessor=current_export,
        base_export=current_export,
        call_count=0,
    }

    ---Preserves the predecessor and paints a conflicting final sentinel.
    ---@param ... any
    ---@return ...
    record.installed = function(...)
        local results = table.pack(record.predecessor(...))
        record.call_count = record.call_count + 1
        local probe = dfhack.dwarfui and
            dfhack.dwarfui[RENDER_PROBE_SLOT] or nil
        if probe and probe.enabled ~= false then
            gui.Painter.new():seek(probe.x, probe.y):char('F', {
                fg=COLOR_WHITE,
                bg=COLOR_MAGENTA,
            })
            probe.foreign_paint_count =
                (probe.foreign_paint_count or 0) + 1
        end
        return table.unpack(results, 1, results.n)
    end
    hook.manager:mark_wrapper_reorderable(record.installed)
    overlay.render_viewscreen_widgets = record.installed
    return record
end

describe('native minecart zoom tooltip polling', function()
    it('tracks the production action independently of input and UI ownership',
            function()
        local native_subject
        local controls
        local modified_action
        local initially_open
        local initial_scroll
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
            assert.is_equal(controls.action, state.target,
                'recreated Hauling action did not become the tooltip target')
            assert.is_table(reqscript('dwarfui/tooltip_service').service:
                get_registrations()[controls.action],
                'recreated Hauling action was not automatically registered')
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
        cleanup_step('release native render observation', function()
            if not native_subject then return end
            ds.unmount()
            native_subject = nil
        end)
        cleanup_step('restore current DwarfUI runtime', function()
            dfhack.run_command('dwarfui', 'reload')
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

describe('native minecart zoom tooltip final rendering', function()
    it('paints after native overlays and repaired foreign wrappers',
            function()
        local native_subject
        local controls
        local staged
        local probe
        local foreign
        local initially_open
        local initial_scroll
        local environment

        local ok, failure = xpcall(function()
            native_subject = ds.mountNativeScreen()
            initially_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_open then
                ds.input('LEAVESCREEN')
                ds.await('pre-existing Hauling menu closes', function()
                    return ds.hasFocus('dwarfmode/Default')
                end)
            end
            ds.input('D_HAULING')
            ds.await('native Hauling menu opens for final rendering',
                function()
                    return ds.hasFocus('dwarfmode/Hauling')
                end)

            local hauling = assert(df.global.plotinfo.hauling,
                'native Hauling state is unavailable')
            initial_scroll = hauling.scroll_position
            environment = capture_environment(native_subject)
            staged = ds.stage_overlay_registration(
                RENDER_OVERLAY_SOURCE, 'tooltip_final_native')
            controls = resolve_controls()
            local stop = reveal_action(hauling, controls)

            local zoom_x, zoom_y, state = select_zoom_action(controls)
            assert.equals(zoom_x, state.intent.anchor_x)
            assert.equals(zoom_y, state.intent.anchor_y)
            local text_x, text_y = tooltip_text_cell(state.intent)
            probe = {
                enabled=true,
                x=text_x,
                y=text_y,
                overlay_paint_order={},
                foreign_paint_count=0,
            }
            dfhack.dwarfui[RENDER_PROBE_SLOT] = probe

            local minimum_rendered_revision = state.intent.revision
            local viewscreen_before = staged_overlay_render_count(
                staged, 'viewscreen_probe')
            local all_before = staged_overlay_render_count(
                staged, 'all_probe')
            ds.redraw()
            assert.same({'V', 'A'}, probe.overlay_paint_order)
            assert.equals(viewscreen_before + 1,
                staged_overlay_render_count(
                    staged, 'viewscreen_probe'))
            assert.equals(all_before + 1,
                staged_overlay_render_count(staged, 'all_probe'))
            assert.equals('Z', read_character(text_x, text_y),
                'tooltip was not final above both overlay groups')
            state = ds.tooltip_state()
            assert_native_render_diagnostics(
                state, minimum_rendered_revision, false)
            assert_environment(environment, native_subject,
                'native tooltip final rendering')

            probe.overlay_paint_order = {}
            ds.move_pointer(stop.x, stop.y)
            ds.await('moving off clears the rendered zoom tooltip',
                function()
                    local current = ds.tooltip_state()
                    return current.target == nil and
                        current.intent == nil
                end)
            probe.overlay_paint_order = {}
            ds.redraw()
            assert.same({'V', 'A'}, probe.overlay_paint_order)
            assert.equals('A', read_character(text_x, text_y),
                'tooltip cells were not restored by the normal render pass')
            assert_environment(environment, native_subject,
                'native tooltip clearing')

            zoom_x, zoom_y, state = select_zoom_action(controls)
            text_x, text_y = tooltip_text_cell(state.intent)
            probe.x, probe.y = text_x, text_y
            foreign = install_foreign_overlay_wrapper()
            local pending = ds.tooltip_state()
            assert.is_false(pending.render_hook.overlay.outermost)
            assert.is_true(
                pending.render_hook.overlay.method_replacement_pending)

            zoom_x, zoom_y =
                ds.move_pointer(controls.zoom_subject, 'top_left')
            ds.await('intent notification repairs around foreign wrapper',
                function()
                    local current = ds.tooltip_state()
                    return current.intent and
                        current.intent.anchor_x == zoom_x and
                        current.intent.anchor_y == zoom_y and
                        current.render_hook.overlay.outermost and
                        current.render_hook.overlay.repair_count > 0 and
                        current.render_hook.overlay.
                            method_replacement_count > 0
                end)
            state = ds.tooltip_state()
            text_x, text_y = tooltip_text_cell(state.intent)
            probe.x, probe.y = text_x, text_y
            probe.overlay_paint_order = {}
            local foreign_before = foreign.call_count
            local foreign_paints_before = probe.foreign_paint_count
            local presenter_renders_before =
                state.presenter.render_count
            minimum_rendered_revision = state.intent.revision
            viewscreen_before = staged_overlay_render_count(
                staged, 'viewscreen_probe')
            all_before = staged_overlay_render_count(
                staged, 'all_probe')
            ds.redraw()
            state = ds.tooltip_state()
            assert.equals(foreign_before + 1, foreign.call_count)
            assert.equals(foreign_paints_before + 1,
                probe.foreign_paint_count)
            assert.equals(presenter_renders_before + 1,
                state.presenter.render_count,
                'one native render invoked the tooltip more than once')
            assert.equals(viewscreen_before + 1,
                staged_overlay_render_count(
                    staged, 'viewscreen_probe'))
            assert.equals(all_before + 1,
                staged_overlay_render_count(staged, 'all_probe'))
            assert.same({'V', 'A'}, probe.overlay_paint_order)
            assert.equals('Z', read_character(text_x, text_y),
                'tooltip did not paint after the foreign wrapper')
            assert_native_render_diagnostics(
                state, minimum_rendered_revision, true)
            assert_environment(environment, native_subject,
                'foreign wrapper repair')

            local module_generation_before =
                state.poller_module_generation
            local presenter_generation_before =
                state.presenter.generation
            local hook_generation_before =
                state.render_hook.generation
            dfhack.run_command('dwarfui', 'reload')
            ds.await('native tooltip generations recover after reload',
                function()
                    local current = ds.tooltip_state()
                    return current.poller_module_generation ==
                            module_generation_before + 1 and
                        current.presenter.generation ==
                            presenter_generation_before + 1 and
                        current.render_hook.generation ==
                            hook_generation_before + 1 and
                        current.poller_current and
                        current.presenter.active and
                        current.render_hook.presenter_installed
                end)

            controls = resolve_controls()
            stop = reveal_action(hauling, controls)
            zoom_x, zoom_y, state = select_zoom_action(controls)
            text_x, text_y = tooltip_text_cell(state.intent)
            probe.x, probe.y = text_x, text_y
            probe.overlay_paint_order = {}
            foreign_before = foreign.call_count
            foreign_paints_before = probe.foreign_paint_count
            presenter_renders_before = state.presenter.render_count
            minimum_rendered_revision = state.intent.revision
            viewscreen_before = staged_overlay_render_count(
                staged, 'viewscreen_probe')
            all_before = staged_overlay_render_count(
                staged, 'all_probe')
            ds.redraw()
            state = ds.tooltip_state()
            assert.equals(foreign_before + 1, foreign.call_count)
            assert.equals(foreign_paints_before + 1,
                probe.foreign_paint_count)
            assert.equals(presenter_renders_before + 1,
                state.presenter.render_count,
                'reload produced duplicate tooltip painting')
            assert.equals(viewscreen_before + 1,
                staged_overlay_render_count(
                    staged, 'viewscreen_probe'))
            assert.equals(all_before + 1,
                staged_overlay_render_count(staged, 'all_probe'))
            assert.same({'V', 'A'}, probe.overlay_paint_order)
            assert.equals('Z', read_character(text_x, text_y))
            assert_native_render_diagnostics(
                state, minimum_rendered_revision, true)
            assert_environment(environment, native_subject,
                'native tooltip reload recovery')
        end, debug.traceback)

        local cleanup_failures = {}

        ---Runs one cleanup step without suppressing later restoration.
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

        cleanup_step('disable final-render sentinels', function()
            if probe then probe.enabled = false end
        end)
        cleanup_step('retire tooltip render hooks', function()
            reqscript('dwarfui/tooltip_render_hook').manager:shutdown()
        end)
        cleanup_step('restore foreign and displaced overlay wrappers',
            function()
                if not foreign then return end
                local current = overlay.render_viewscreen_widgets
                assert.is_true(current == foreign.installed or
                    current == foreign.predecessor,
                    'unexpected overlay wrapper remained during cleanup')
                overlay.render_viewscreen_widgets = foreign.base_export
                foreign = nil
            end)
        cleanup_step('clear production overlay state', function()
            if controls and controls.overlay then
                controls.overlay:clear_overlay_state()
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
        cleanup_step('release native render observation', function()
            if not native_subject then return end
            ds.unmount()
            native_subject = nil
        end)
        cleanup_step('clear final-render process probe', function()
            if dfhack.dwarfui then
                dfhack.dwarfui[RENDER_PROBE_SLOT] = nil
            end
            probe = nil
        end)
        cleanup_step('restore current DwarfUI runtime', function()
            dfhack.run_command('dwarfui', 'reload')
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
