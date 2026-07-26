-- Live component contracts for the native mood-icon popover overlay.

local mood_overlay = reqscript('dwarfui-mood-popover')

local MoodPopoverOverlay = mood_overlay.MoodPopoverOverlay
local MoodPopoverModel = reqscript('dwarfui/mood_popover').MoodPopoverModel
local REGISTERED_WIDGET = 'dwarfui-mood-popover.mood_popover'
local state
local root

---Returns whether the current native screen contains a CP437 text fragment.
---@param text string
---@return boolean
local function native_screen_contains(text)
    local expected = text:lower()
    local width, height = dfhack.screen.getWindowSize()
    for y=0,height - 1 do
        local row = {}
        for x=0,width - 1 do
            local tile = dfhack.screen.readTile(x, y)
            row[#row + 1] = string.char(tile and tile.ch or 0)
        end
        if table.concat(row):lower():find(expected, 1, true) then return true end
    end
    return false
end

---Parses the rendered popover heading into its category and row count.
---@param text string|nil
---@return string, integer
local function parse_header(text)
    local label, count
    if text then label, count = text:match('^(.-) %((%d+)%)$') end
    assert(label and count,
        ('invalid mood popover header: %s'):format(tostring(text)))
    return label, tonumber(count)
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

---Returns the rendered CP437 character codes in one inspected rectangle.
---@param name string
---@param bounds {x1: integer, y1: integer, x2: integer, y2: integer}
---@return string
local function captured_cp437(name, bounds)
    local capture = ds.capture_screen(name, {
        max_width=bounds.x2 + 1,
        max_height=bounds.y2 + 1,
    })
    local lines = {}
    for y=bounds.y1,bounds.y2 do
        local row = {}
        for x=bounds.x1,bounds.x2 do
            local cell = captured_cell(capture, x, y)
            row[#row + 1] = string.char(cell and cell.ch or 0)
        end
        lines[#lines + 1] = table.concat(row)
    end
    return table.concat(lines, '\n')
end

---Returns the integer rendered in one native moodlet count row.
---@param rect {x1: integer, x2: integer, y2: integer}
---@return integer
local function rendered_mood_count(rect)
    local digits = {}
    for x=rect.x1,rect.x2 do
        local tile = dfhack.screen.readTile(x, rect.y2)
        if tile and tile.ch >= string.byte('0') and
                tile.ch <= string.byte('9') then
            digits[#digits + 1] = string.char(tile.ch)
        end
    end
    return assert(tonumber(table.concat(digits)),
        'native moodlet has no rendered count')
end

describe('live mood popover overlay registration', function()
    it('is discovered and renders injected data across the active screen',
            function()
        local overlay = require('plugins.overlay')
        overlay.rescan()

        local name = 'dwarfui-mood-popover.mood_popover'
        local entry = assert(overlay.get_state().db[name],
            ('overlay is not registered: %s'):format(name))
        local widget = assert(entry.widget, 'registered overlay has no instance')
        assert.is_true(widget.fullscreen)
        assert.is_true(widget.hotspot)
        assert.equals(widget.frame_parent_rect.width, widget.frame_rect.width)
        assert.equals(widget.frame_parent_rect.height, widget.frame_rect.height)
        assert.equals(0, widget.frame_rect.x1)
        assert.equals(0, widget.frame_rect.y1)
        assert.is_true(widget.active_provider())

        for _, descriptor in ipairs(widget.mood_model:get_descriptors()) do
            local live_rows = widget.mood_model:build_active_snapshot(descriptor)
            assert.equals('table', type(live_rows))
            for index, row in ipairs(live_rows) do
                assert.equals(descriptor.stress_category,
                    dfhack.units.getStressCategory(row.unit))
                if index > 1 then
                    local previous_stress = live_rows[index - 1].stress
                    if descriptor.stress_descending then
                        assert.is_true(previous_stress >= row.stress)
                    else
                        assert.is_true(previous_stress <= row.stress)
                    end
                end
            end
        end

        local old_hover = widget.hover_provider
        local old_mouse = widget.mouse_provider
        local old_snapshot = widget.snapshot_provider
        local old_active = widget.active_provider
        local ok, failure = xpcall(function()
            widget.active_provider = function() return true end
            widget.hover_provider = function()
                return df.main_hover_instruction.INFO_STRESSED_0
            end
            widget.mouse_provider = function() return 10, 3 end
            widget.snapshot_provider = function()
                return {{id=1, name='Registered Citizen'}}
            end
            ds.wait_frames(2)
            assert.equals('Ecstatic', widget.selected_descriptor.label)
            assert.is_true(widget.popover.visible)
            assert.equals('Ecstatic (1)', widget.popover.header.text)
        end, debug.traceback)
        widget.hover_provider = old_hover
        widget.mouse_provider = old_mouse
        widget.snapshot_provider = old_snapshot
        widget.active_provider = old_active
        widget:clear()
        assert.is_true(ok, failure)
    end)
end)

describe('registered mood overlay with native top-bar data', function()
    it('routes native moodlet hover, scrolling, and unit selection', function()
        local borrowed_screen = assert(dfhack.gui.getDFViewscreen(true),
            'native fortress viewscreen is unavailable')
        local sheets = df.global.game.main_interface.view_sheets
        local indicator = df.global.game.main_interface.recenter_indicator_m
        local saved_unids = {}
        for _, unit_id in ipairs(sheets.viewing_unid) do
            saved_unids[#saved_unids + 1] = unit_id
        end
        local saved = {
            window_x=df.global.window_x,
            window_y=df.global.window_y,
            window_z=df.global.window_z,
            sheet_open=sheets.open,
            sheet_context=sheets.context,
            active_sheet=sheets.active_sheet,
            active_id=sheets.active_id,
            viewing_x=sheets.viewing_x,
            viewing_y=sheets.viewing_y,
            viewing_z=sheets.viewing_z,
            scroll_position=sheets.scroll_position,
            active_sub_tab=sheets.active_sub_tab,
            last_tick_update=sheets.last_tick_update,
            indicator_x=indicator.x,
            indicator_y=indicator.y,
            indicator_z=indicator.z,
        }
        local native_subject
        local popover_subject
        local ok, failure = xpcall(function()
            -- Attach to the game-owned fortress screen without creating a host
            -- or taking ownership of the existing native viewscreen.
            native_subject = ds.mountNativeScreen()
            assert.is_true(ds.hasFocus('dwarfmode/Default'))

            local source = {
                source='overlay',
                overlay=REGISTERED_WIDGET,
            }
            local header_subject
            local list_subject
            ds.await('registered mood popover controls become addressable',
                function()
                    local popover_ok, selected_popover = pcall(ds.get,
                        'mood_popover', source)
                    local header_ok, selected_header = pcall(ds.get,
                        'mood_popover/header', source)
                    local list_ok, selected_list = pcall(ds.get,
                        'mood_popover/list', source)
                    if not (popover_ok and header_ok and list_ok) then
                        return false
                    end
                    popover_subject = selected_popover
                    header_subject = selected_header
                    list_subject = selected_list
                    return true
                end)

            local display = mood_overlay.TopBarMoodDisplay{}
            local moodlets = assert(display:find_layout(),
                'rendered top information-bar moodlets are unavailable')
            local descriptors = MoodPopoverModel{}:get_descriptors()
            assert.equals(7, #moodlets)
            assert.equals(#moodlets, #descriptors)

            local overflow_index
            for index, descriptor in ipairs(descriptors) do
                local rect = moodlets[index]
                local expected_hover = df.main_hover_instruction[
                    'INFO_STRESSED_' .. (index - 1)]

                -- Every cell in the complete two-column information-bar hit
                -- region is real input evidence: both icon cells, the number
                -- row, and the surrounding cells above and below its graphic.
                for y=rect.y1,rect.y2 do
                    for x=rect.x1,rect.x2 do
                        assert.equals(expected_hover,
                            display:resolve_hover(x, y))
                        ds.move_pointer(x, y)
                        ds.redraw()
                        local label, count = parse_header(
                            header_subject:text())
                        assert.equals(descriptor.label, label)
                        assert.equals(rendered_mood_count(rect), count)
                        assert.is_true(popover_subject:inspect().visible,
                            ('mood popover closed at moodlet %d cell %d,%d')
                                :format(index, x, y))
                    end
                end

                local list_state = list_subject:inspect()
                assert.is_table(popover_subject:inspect().frame)
                assert.is_table(list_state.body)
                assert.equals(1, list_state.scroll_position)
                if rendered_mood_count(rect) >
                        (list_state.visible_row_count or 0) then
                    local rows = popover_subject:raw().rows
                    for _, row in ipairs(rows) do
                        local soul = row.unit and row.unit.status and
                            row.unit.status.current_soul
                        if soul and #soul.skills > 0 then
                            overflow_index = index
                            break
                        end
                    end
                end
            end
            assert.is_not_nil(overflow_index,
                'prepared fortress has no overflowing mood with overview data')

            -- Reopen one naturally populated overflowing category, then keep
            -- the pointer on the native moodlet while the registered overlay
            -- consumes exactly one wheel step.
            local rect = moodlets[overflow_index]
            ds.move_pointer(rect.x1, rect.y2)
            ds.redraw()
            local list_before_moodlet_scroll = list_subject:inspect()
            local z_before_moodlet_scroll = df.global.window_z
            ds.mouseInput(ds.EMouseButton.SCROLL_DOWN)
            local list_after_moodlet_scroll = list_subject:inspect()
            assert.equals(list_before_moodlet_scroll.scroll_position + 1,
                list_after_moodlet_scroll.scroll_position)
            assert.equals(z_before_moodlet_scroll, df.global.window_z)

            -- Cross the one-row retention bridge into the inspected list body.
            -- Normal render-time hover must retain the open popover.
            local list_bounds = assert(list_after_moodlet_scroll.body)
            ds.move_pointer(list_bounds.x1 + 1, list_bounds.y1)
            ds.redraw()
            assert.is_true(popover_subject:inspect().visible)

            -- Scrolling over the list updates DwarfSpec's inspected list state
            -- and changes the actual rendered rows in the same direction.
            local before_text = captured_cp437(
                'mood_popover_rows_before_scroll', list_bounds)
            local before_list_scroll = list_subject:inspect().scroll_position
            ds.mouseInput(ds.EMouseButton.SCROLL_DOWN)
            local after_list_state = list_subject:inspect()
            local after_text = captured_cp437(
                'mood_popover_rows_after_scroll',
                assert(after_list_state.body))
            assert.equals(before_list_scroll + 1,
                after_list_state.scroll_position)
            assert.is_false(before_text == after_text,
                'list scroll state changed without changing rendered rows')

            -- Resolve the row currently occupying the clicked rendered line.
            -- The row identity is evidence only; activation still travels from
            -- DwarfSpec through the registered overlay's natural input path.
            local list = list_subject:raw()
            local choice
            local choice_index
            local first_visible = after_list_state.scroll_position
            local last_visible = math.min(#list.choices,
                first_visible + after_list_state.visible_row_count - 1)
            for index=first_visible,last_visible do
                local candidate = list.choices[index]
                local unit = candidate and candidate.row and candidate.row.unit
                local soul = unit and unit.status and unit.status.current_soul
                if soul and #soul.skills > 0 then
                    choice = candidate
                    choice_index = index
                    break
                end
            end
            assert.is_not_nil(choice,
                'visible mood rows contain no unit with overview skill data')
            local target = assert(choice.row and choice.row.unit,
                'visible mood row has no native unit')
            local rendered_row = choice.text
            assert.is_truthy(after_text:find(rendered_row, 1, true),
                ('selected unit row %q is not present in captured rendering %q')
                    :format(choice.text, after_text))
            ds.move_pointer(after_list_state.body.x1 + 1,
                after_list_state.body.y1 +
                    (choice_index - after_list_state.scroll_position))
            ds.redraw()
            ds.mouseInput(ds.EMouseButton.LEFT)

            assert.is_true(sheets.open)
            assert.equals(df.view_sheet_type.UNIT, sheets.active_sheet)
            assert.equals(target.id, sheets.active_id)
            assert.equals(target.id, dfhack.gui.getSelectedUnit(true).id)
            assert.equals(target.pos.x, sheets.viewing_x)
            assert.equals(target.pos.y, sheets.viewing_y)
            assert.equals(target.pos.z, sheets.viewing_z)
            assert.equals(0, sheets.scroll_position)
            assert.equals(0, sheets.active_sub_tab)
            assert.equals(target.pos.z, df.global.window_z)

            -- The native screen's focus and the overlay's rendered lifecycle
            -- both prove that unit selection left the top-bar context.
            ds.redraw()
            assert.is_false(ds.hasFocus('dwarfmode/Default'))
            assert.is_true(ds.hasFocus('dwarfmode/ViewSheets'))
            assert.is_false(popover_subject:inspect().visible)

            -- The default Overview tab must contain real unit-card data, not
            -- merely an open shell with the selected unit ID.
            local overview_name = assert(target.name.first_name ~= '' and
                target.name.first_name,
                'selected citizen has no first name')
            ds.wait_frames(3)
            local overview_name_visible = native_screen_contains(overview_name)
            local thought_count = #sheets.raw_thought_str
            local skill_count = sheets.labor_skill_num
            if not overview_name_visible or thought_count == 0 or
                    skill_count == 0 then
                local width, height = dfhack.screen.getWindowSize()
                local screen_text = captured_cp437('unit_card_overview', {
                    x1=0, y1=0, x2=width - 1, y2=height - 1,
                })
                error(('unit %d overview is unpopulated: name=%q visible=%s ' ..
                    'thoughts=%d skills=%d soul_skills=%d screen=%q')
                    :format(target.id, overview_name,
                        tostring(overview_name_visible), thought_count,
                        skill_count, #target.status.current_soul.skills,
                        screen_text))
            end
        end, debug.traceback)

        -- Release the borrowed attachment before restoring all game-owned
        -- viewport and unit-card state. DwarfSpec restores pointer state.
        local popover_cleanup = popover_subject and popover_subject:raw() or nil
        if native_subject then ds.unmount() end
        df.global.window_x = saved.window_x
        df.global.window_y = saved.window_y
        df.global.window_z = saved.window_z
        sheets.open = saved.sheet_open
        sheets.context = saved.sheet_context
        sheets.active_sheet = saved.active_sheet
        sheets.active_id = saved.active_id
        sheets.viewing_x = saved.viewing_x
        sheets.viewing_y = saved.viewing_y
        sheets.viewing_z = saved.viewing_z
        sheets.scroll_position = saved.scroll_position
        sheets.active_sub_tab = saved.active_sub_tab
        sheets.last_tick_update = saved.last_tick_update
        sheets.viewing_unid:resize(0)
        for _, unit_id in ipairs(saved_unids) do
            sheets.viewing_unid:insert('#', unit_id)
        end
        indicator.x = saved.indicator_x
        indicator.y = saved.indicator_y
        indicator.z = saved.indicator_z
        if popover_cleanup then
            if popover_cleanup.parent_view and
                    popover_cleanup.parent_view.clear then
                popover_cleanup.parent_view:clear()
            end
        end
        borrowed_screen:logic()
        borrowed_screen:render(df.global.cur_year_tick)
        assert.is_equal(borrowed_screen, dfhack.gui.getDFViewscreen(true),
            'native attachment dismissed or replaced the game screen')
        assert.is_true(ok, failure)
    end)
end)

---Builds readable deterministic rows for one injected mood descriptor.
---@param descriptor table
---@param count integer|nil
---@return table[]
local function rows_for(descriptor, count)
    local rows = {}
    for index=1,count or descriptor.hover_index + 1 do
        table.insert(rows, {
            id=descriptor.hover_index * 100 + index,
            name=('%s Unit %02d'):format(descriptor.label, index),
        })
    end
    return rows
end

---Creates one mounted overlay with entirely injected live-test providers.
---@param overrides? table
---@return table
local function mount_overlay(overrides)
    local attributes = {
        initial_pause=false,
        viewport={width=80, height=25},
        hover_provider=function() return state.hover end,
        mouse_provider=function() return state.mouse_x, state.mouse_y end,
        snapshot_provider=function(descriptor)
            return state.rows[descriptor.hover_index] or {}
        end,
        active_provider=function() return state.active end,
        refresh_interval=1,
    }
    for key, value in pairs(overrides or {}) do attributes[key] = value end
    return ds.mount(MoodPopoverOverlay, attributes)
end

---Selects one injected mood value at a deterministic screen position.
---@param hover_index integer
---@param x integer
---@param y integer
local function select_mood(hover_index, x, y)
    state.hover = df.main_hover_instruction['INFO_STRESSED_' .. hover_index]
    state.mouse_x, state.mouse_y = x, y
    root:raw():update_popover()
    ds.wait_frames(1)
end

---Returns the mounted reusable popover and its stable controls.
---@return table, table, table
local function popover_controls()
    return ds.get('mood_popover'), ds.get('mood_popover/header'),
        ds.get('mood_popover/list')
end

describe('mounted mood popover component with injected providers', function()
    before_each(function()
        state = {active=true, hover=nil, mouse_x=nil, mouse_y=nil, rows={}}
        for index=0,6 do
            state.rows[index] = rows_for({
                hover_index=index,
                label=({'Ecstatic', 'Very Happy', 'Happy', 'Content',
                    'Unhappy', 'Very Unhappy', 'Miserable'})[index + 1],
            })
        end
        root = mount_overlay()
    end)

    it('renders every injected mood heading, count, and row set',
            function()
        local labels = {'Ecstatic', 'Very Happy', 'Happy', 'Content',
            'Unhappy', 'Very Unhappy', 'Miserable'}
        for index, label in ipairs(labels) do
            local hover_index = index - 1
            select_mood(hover_index, 8 + hover_index, 3)
            local _, header, list = popover_controls()
            assert.equals(('%s (%d)'):format(label, hover_index + 1),
                header:text())
            assert.equals(hover_index + 1, #list:raw().choices)
            assert.equals(('%s Unit 01'):format(label),
                list:raw().choices[1].text)
        end
    end)

    it('retains the current mood when injected hover yields to its panel',
            function()
        select_mood(0, 10, 3)
        local popover = ds.get('mood_popover')
        local body = assert(popover:inspect().body)
        state.hover = nil
        state.mouse_x = math.floor((body.x1 + body.x2) / 2)
        state.mouse_y = math.floor((body.y1 + body.y2) / 2)
        popover:move_pointer('center')
        root:raw():update_popover()
        ds.wait_frames(1)

        assert.equals('Ecstatic', root:raw().selected_descriptor.label)
        assert.is_true(popover:inspect().visible)
    end)

    it('handles direct wheel input while the injected mood remains selected',
            function()
        state.rows[3] = rows_for({hover_index=3, label='Content'}, 20)
        select_mood(3, 10, 3)
        local popover, _, list = popover_controls()
        local scrollbar = list:raw().scrollbar
        local initial_offset = scrollbar.bar_offset
        assert.is_true(root:raw():onInput({CONTEXT_SCROLL_DOWN=true}))
        assert.equals(2, list:raw().page_top)
        assert.equals(2, scrollbar.top_elem)
        assert.is_true(scrollbar.bar_offset > initial_offset)
        root:raw():update_popover()
        assert.equals(2, list:raw().page_top)
        assert.equals(2, scrollbar.top_elem)
        for _=1,20 do
            assert.is_true(root:raw():onInput({CONTEXT_SCROLL_DOWN=true}))
        end
        assert.equals(20 - root:raw().popover.visible_rows + 1,
            list:raw().page_top)
        assert.equals(list:raw().page_top, scrollbar.top_elem)
        assert.is_true(scrollbar.bar_offset > initial_offset)
        assert.equals('Content Unit 20', list:raw().choices[20].text)

        state.hover, state.mouse_x, state.mouse_y = nil, 0, 0
        root:raw():update_popover()
        ds.wait_frames(1)
        assert.is_nil(root:raw():onInput({_MOUSE_L=true}))
        assert.is_nil(root:raw():onInput({CUSTOM_A=true}))
        assert.is_nil(root:raw():onInput({CONTEXT_SCROLL_DOWN=true}))
        assert.is_false(popover:inspect().visible)
    end)

    it('handles pointer loss, direct changes, empty rows, and viewport bounds',
            function()
        select_mood(1, 10, 5)
        local first_anchor = root:raw().popover.frame_global
        assert.equals(6, first_anchor.y)

        select_mood(6, 79, 23)
        local popover, header, list = popover_controls()
        local frame = root:raw().popover.frame_global
        assert.is_true(frame.y < 23)
        assert.is_true(frame.x + frame.w <= 80)
        assert.equals('Miserable (7)', header:text())

        state.rows[2] = {}
        select_mood(2, 10, 3)
        assert.equals('Happy (0)', header:text())
        assert.is_false(list:inspect().visible)
        assert.is_true(root:raw():onInput({CONTEXT_SCROLL_DOWN=true}))
        assert.equals(1, list:raw().page_top)

        ds.viewport(30, 10)
        frame = root:raw().popover.frame_global
        assert.is_true(frame.x >= 0 and frame.x + frame.w <= 30)
        assert.is_true(frame.y >= 0 and frame.y + frame.h <= 10)

        state.mouse_x = nil
        root:raw():update_popover()
        ds.wait_frames(1)
        assert.is_nil(root:raw().selected_descriptor)
        assert.is_false(popover:inspect().visible)
    end)

    it('cleans state on unmount and begins a remount without stale rows',
            function()
        select_mood(4, 10, 3)
        local first = root:raw()
        assert.equals('Unhappy', first.selected_descriptor.label)
        ds.unmount()
        assert.is_nil(first.selected_descriptor)
        assert.same({}, first.popover.rows)

        state.hover, state.mouse_x, state.mouse_y = nil, nil, nil
        root = mount_overlay()
        local popover, header, list = popover_controls()
        assert.is_nil(root:raw().selected_descriptor)
        assert.equals(' (0)', header:text())
        assert.is_false(popover:inspect().visible)
        assert.equals(1, list:raw().page_top)
        assert.same({}, list:raw().choices)
    end)
end)
