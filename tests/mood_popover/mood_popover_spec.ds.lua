-- Live component contracts for the native mood-icon popover overlay.

local mood_overlay = reqscript('dwarfui-mood-popover')

local MoodPopoverOverlay = mood_overlay.MoodPopoverOverlay
local state
local root

describe('live mood popover overlay registration', function()
    it('is discovered under its canonical name and fills the active screen',
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

describe('native DF top-bar moodlet integration', function()
    it('detects pointer hover over every rendered native moodlet', function()
        local screen = assert(dfhack.gui.getDFViewscreen(true),
            'native fortress viewscreen is unavailable')
        assert.is_true(dfhack.gui.matchFocusString(
            'dwarfmode/Default', screen))
        local overlay = require('plugins.overlay')
        overlay.rescan()
        ds.wait_frames(2)

        local name = 'dwarfui-mood-popover.mood_popover'
        local entry = assert(overlay.get_state().db[name],
            ('overlay is not registered: %s'):format(name))
        local widget = assert(entry.widget, 'registered overlay has no instance')
        assert.is_true(widget.active_provider())
        assert.equals(require('gui').FRAME_THIN,
            widget.popover.frame_style)

        local display = mood_overlay.TopBarMoodDisplay{}
        local moodlets = assert(display:find_layout(),
            'rendered top information-bar moodlets are unavailable')
        assert.equals(7, #moodlets)
        local gps = df.global.gps
        local enabler = df.global.enabler
        local saved = {
            mouse_x=gps.mouse_x,
            mouse_y=gps.mouse_y,
            precise_mouse_x=gps.precise_mouse_x,
            precise_mouse_y=gps.precise_mouse_y,
            mouse_focus=enabler.mouse_focus,
            tracking_on=enabler.tracking_on,
        }

        local labels = {'Ecstatic', 'Very Happy', 'Happy', 'Content',
            'Unhappy', 'Very Unhappy', 'Miserable'}
        local ok, failure = xpcall(function()
            enabler.mouse_focus = true
            enabler.tracking_on = 1
            for index, expected_label in ipairs(labels) do
                local rect = moodlets[index]
                local tile = assert(dfhack.screen.readTile(rect.x1, rect.y1))
                assert.equals(0, tile.ch)

                local expected_hover = df.main_hover_instruction[
                    'INFO_STRESSED_' .. (index - 1)]
                for y=rect.y1,rect.y2 do
                    for x=rect.x1,rect.x2 do
                        assert.equals(expected_hover,
                            display:resolve_hover(x, y))
                    end
                end
                gps.mouse_x, gps.mouse_y = rect.x1, rect.y2
                gps.precise_mouse_x = rect.x1 * gps.tile_pixel_x + 1
                gps.precise_mouse_y = rect.y2 * gps.tile_pixel_y + 1
                widget:update_popover()
                assert.equals(expected_label,
                    widget.selected_descriptor.label)
                assert.is_true(widget.popover.visible)
                assert.equals(expected_label, widget.popover.title)
                assert.equals(rect.y2 + 2, widget.popover.frame_global.y)

                local displayed_count = ''
                for x=rect.x1,rect.x2 do
                    local count_tile = dfhack.screen.readTile(x, rect.y2)
                    if count_tile.ch >= string.byte('0') and
                            count_tile.ch <= string.byte('9') then
                        displayed_count = displayed_count ..
                            string.char(count_tile.ch)
                    end
                end
                assert.equals(tonumber(displayed_count), #widget.popover.rows)
            end
        end, debug.traceback)

        gps.mouse_x, gps.mouse_y = saved.mouse_x, saved.mouse_y
        gps.precise_mouse_x = saved.precise_mouse_x
        gps.precise_mouse_y = saved.precise_mouse_y
        enabler.mouse_focus = saved.mouse_focus
        enabler.tracking_on = saved.tracking_on
        widget:clear()
        screen:logic()
        screen:render(df.global.cur_year_tick)
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

---Selects one injected native mood icon at a deterministic screen position.
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

describe('live mood popover overlay component', function()
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

    it('renders every injected native mood heading, count, and row set',
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

    it('retains the current mood when the native hover yields to its panel',
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

    it('scrolls every injected row and leaves external input unhandled',
            function()
        state.rows[3] = rows_for({hover_index=3, label='Content'}, 20)
        select_mood(3, 10, 3)
        local popover, _, list = popover_controls()
        local body = assert(list:inspect().body)
        state.hover = nil
        state.mouse_x = math.floor((body.x1 + body.x2) / 2)
        state.mouse_y = math.floor((body.y1 + body.y2) / 2)
        list:move_pointer('center')
        root:raw():update_popover()
        ds.wait_frames(1)
        for _=1,20 do root:input('STANDARDSCROLL_DOWN') end
        assert.equals(20 - root:raw().popover.visible_rows + 1,
            root:raw().popover.scroll_top)
        assert.equals(root:raw().popover.scroll_top, list:raw().page_top)
        assert.equals('Content Unit 20', list:raw().choices[20].text)

        state.mouse_x, state.mouse_y = 0, 0
        root:raw():update_popover()
        ds.wait_frames(1)
        assert.is_nil(root:raw():onInput({_MOUSE_L=true}))
        assert.is_nil(root:raw():onInput({CUSTOM_A=true}))
        assert.is_nil(root:raw():onInput({STANDARDSCROLL_DOWN=true}))
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
        assert.equals(1, root:raw().popover.scroll_top)
        assert.same({}, list:raw().choices)
    end)
end)
