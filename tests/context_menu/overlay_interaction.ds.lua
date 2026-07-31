-- Native registered-overlay context-menu interaction acceptance.

local gui = require('gui')
local context_menu = reqscript('dwarfui/context_menu/api')
local services = reqscript('dwarfui/context_menu/service')

local OVERLAY_SOURCE =
    'tests/context_menu/support/context_menu_overlay_registration.lua'
local PROCESS_STATE_SLOT = 'context_menu_component_probe'

---Returns the live context-menu service.
---@return dwarfui.ContextMenuService
local function service()
    return services.service
end

---Returns the test-owned process observation state.
---@return table
local function probe_state()
    return assert(dfhack.dwarfui[PROCESS_STATE_SLOT],
        'context-menu overlay probe state is unavailable')
end

---Returns the active production context-menu screen.
---@return dwarfui.ContextMenuScreen
local function menu_screen()
    local presentation = assert(service()._state.presentation,
        'context-menu presentation is unavailable')
    return assert(presentation.screen,
        'context-menu presentation has no screen')
end

---Feeds one table through the current production viewscreen.
---@param keys table
local function feed_current(keys)
    gui.simulateInput(dfhack.gui.getCurViewscreen(), keys)
    ds.redraw()
end

---Returns whether the most recent backing-overlay input contains a key.
---@param key string
---@return boolean
local function last_backing_input_has(key)
    local inputs = probe_state().inputs
    local last = inputs[#inputs]
    return last ~= nil and not not last[key]
end

---Opens the widget menu through the native overlay input boundary.
---@param x integer
---@param y integer
---@param keys? table
local function open_widget_menu(x, y, keys)
    assert.is_false(service():is_open())
    ds.move_pointer(x, y)
    ds.input(keys or {_MOUSE_R=true})
    ds.await('registered overlay context menu opens', function()
        return service():is_open()
    end)
end

describe('native registered-overlay context menu', function()
    it('owns actionable tables and delegates unrelated input', function()
        local native_subject
        local target
        local overlay_widget
        local initially_hauling_open
        local initial_pause
        local ok, failure = xpcall(function()
            ds.mountSaveGame('current')
            service():clear_world_state()
            native_subject = ds.mountNativeScreen()
            initially_hauling_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_hauling_open then
                ds.input('LEAVESCREEN')
                ds.await('Hauling closes for context-menu coverage',
                    function() return ds.hasFocus('dwarfmode/Default') end)
            end
            initial_pause = ds.isGamePaused()

            local staged = ds.stage_overlay_registration(
                OVERLAY_SOURCE, 'context_menu_native')
            local overlay_name = assert(staged.registered_names[1],
                'context-menu probe overlay was not registered')
            ds.redraw()
            target = ds.get('context_target', {
                source='overlay',
                overlay=overlay_name,
            }):raw()
            overlay_widget = assert(target.parent_view,
                'context-menu target has no overlay parent')
            local body = assert(target.frame_body,
                'context-menu target has no rendered body')
            local target_x = math.floor((body.x1 + body.x2) / 2)
            local target_y = math.floor((body.y1 + body.y2) / 2)
            local state = probe_state()
            state.inputs = {}
            state.selection_count = 0
            state.selection_context = nil

            ds.move_pointer(target_x, target_y)
            ds.input({_MOUSE_R_DOWN=true})
            assert.is_false(service():is_open())
            assert.is_true(last_backing_input_has('_MOUSE_R_DOWN'),
                'down-only input did not remain transparent')

            local backing_before_open = #state.inputs
            ds.input({_MOUSE_R=true, D_PAUSE=true, CUSTOM_OPEN=true})
            ds.await('mixed native right-click opens menu', function()
                return service():is_open()
            end)
            assert.equals(backing_before_open, #state.inputs,
                'owned opening table reached the backing overlay')
            assert.equals(initial_pause, ds.isGamePaused(),
                'coalesced pause escaped an owned opening table')
            local first_menu = menu_screen()
            assert.same({x=target_x, y=target_y},
                first_menu.anchor.screen_position)
            assert.is_equal(target,
                first_menu.session:create_selection_context().source)

            local first_window = first_menu.menu_window
            local shared_style_before = gui.FRAME_INTERIOR()
            assert.equals(COLOR_LIGHTCYAN,
                first_window.frame_style.frame_pen.fg)
            assert.equals(COLOR_BLUE,
                first_window.frame_style.frame_pen.bg)
            assert.equals(COLOR_LIGHTCYAN,
                first_window.frame_style.title_pen.fg)
            assert.equals(COLOR_BLUE,
                first_window.frame_background.bg)
            assert.equals(COLOR_LIGHTCYAN,
                first_window.menu_list.choices[1].normal_pen.fg)
            assert.equals(COLOR_BLUE,
                first_window.menu_list.choices[1].normal_pen.bg)
            assert.equals(COLOR_LIGHTRED,
                first_window.menu_list.choices[2].normal_pen.fg)
            assert.equals(COLOR_BLACK,
                first_window.menu_list.choices[2].normal_pen.bg)
            local shared_style_after = gui.FRAME_INTERIOR()
            assert.same(shared_style_before, shared_style_after,
                'context-menu colors mutated the shared Window frame style')

            local selection_before = first_window.menu_list.selected
            feed_current{LEAVESCREEN=true, KEYBOARD_CURSOR_DOWN=true}
            assert.is_false(service():is_open())
            assert.equals(selection_before, first_window.menu_list.selected,
                'Escape did not win mixed relevant-key priority')
            assert.equals(0, state.selection_count)

            open_widget_menu(target_x, target_y)
            local second_menu = menu_screen()
            local list = second_menu.menu_window.menu_list
            local backing_before_navigation = #state.inputs
            feed_current{
                KEYBOARD_CURSOR_DOWN=true,
                CUSTOM_NAVIGATION=true,
            }
            assert.equals(2, list.selected)
            assert.equals(backing_before_navigation, #state.inputs,
                'owned list navigation table reached backing UI')
            feed_current{SELECT=true, LEAVESCREEN=true}
            assert.is_false(service():is_open())
            assert.equals(0, state.selection_count,
                'Escape-plus-selection invoked an entry')

            open_widget_menu(target_x, target_y)
            local third_menu = menu_screen()
            local frame = third_menu.menu_window.frame_rect
            ds.move_pointer(frame.x1, frame.y1)
            local backing_before_frame = #state.inputs
            feed_current{_MOUSE_L=true}
            assert.is_true(service():is_open())
            assert.equals(0, state.selection_count)
            assert.equals(backing_before_frame, #state.inputs,
                'Window frame click reached backing UI')

            ds.move_pointer(0, 0)
            feed_current{_MOUSE_L=true, SELECT=true}
            assert.is_false(service():is_open())
            assert.equals(0, state.selection_count,
                'outside click did not win over coalesced selection')
            assert.equals(backing_before_frame, #state.inputs,
                'outside close reached backing UI')

            open_widget_menu(target_x, target_y)
            local backing_before_second_right = #state.inputs
            feed_current{_MOUSE_R=true, CUSTOM_CLOSE=true}
            assert.is_false(service():is_open())
            assert.equals(backing_before_second_right, #state.inputs,
                'second right-click reached backing UI')

            open_widget_menu(target_x, target_y)
            local fourth_menu = menu_screen()
            local row = fourth_menu.menu_window.menu_list.frame_rect
            ds.move_pointer(row.x1 + 1, row.y1)
            local backing_before_select = #state.inputs
            feed_current{_MOUSE_L=true, CUSTOM_SELECT=true}
            assert.is_false(service():is_open())
            assert.equals(1, state.selection_count)
            assert.is_equal(target, state.selection_context.source)
            assert.is_not_nil(state.selection_context.source_root)
            assert.equals(backing_before_select, #state.inputs,
                'mouse selection reached backing UI')

            open_widget_menu(target_x, target_y)
            local backing_before_keyboard = #state.inputs
            feed_current{SELECT=true, CUSTOM_SELECT=true}
            assert.is_false(service():is_open())
            assert.equals(2, state.selection_count)
            assert.is_equal(target, state.selection_context.source)
            assert.is_not_nil(state.selection_context.source_root)
            assert.equals(backing_before_keyboard, #state.inputs,
                'keyboard selection reached backing UI')

            open_widget_menu(target_x, target_y)
            ds.move_pointer(0, 0)
            local backing_before_wheel = #state.inputs
            feed_current{CONTEXT_SCROLL_DOWN=true}
            assert.is_true(service():is_open())
            assert.equals(backing_before_wheel + 1, #state.inputs)
            assert.is_true(last_backing_input_has('CONTEXT_SCROLL_DOWN'))

            local pause_before = ds.isGamePaused()
            feed_current{D_PAUSE=true}
            assert.is_true(service():is_open())
            assert.equals(not pause_before, ds.isGamePaused(),
                'pause-only input did not pass through')
            assert.is_true(last_backing_input_has('D_PAUSE'))
            feed_current{D_PAUSE=true}
            assert.equals(pause_before, ds.isGamePaused())
            feed_current{CUSTOM_IRRELEVANT=true}
            assert.is_true(last_backing_input_has('CUSTOM_IRRELEVANT'))

            service():close()
            target.visible = false
            ds.redraw()
            local backing_before_hidden = #state.inputs
            ds.move_pointer(target_x, target_y)
            ds.input({_MOUSE_R=true})
            assert.is_false(service():is_open())
            assert.is_true(#state.inputs > backing_before_hidden,
                'hidden target did not delegate its right-click miss')
            target.visible = true
            ds.redraw()
            open_widget_menu(target_x, target_y)
            service():close()
        end, debug.traceback)

        if service():is_open() then service():close() end
        if target then context_menu.unregister(target) end
        service():clear_world_state()
        if initial_pause ~= nil and ds.isGamePaused() ~= initial_pause then
            ds.input('D_PAUSE')
            ds.await('original pause state returns',
                function() return ds.isGamePaused() == initial_pause end)
        end
        if native_subject and initially_hauling_open and
                not ds.hasFocus('dwarfmode/Hauling') then
            ds.input('D_HAULING')
            ds.await('original Hauling screen returns',
                function() return ds.hasFocus('dwarfmode/Hauling') end)
        end
        assert.is_true(ok, failure)
    end)
end)
