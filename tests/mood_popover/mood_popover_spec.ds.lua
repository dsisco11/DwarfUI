-- Live component contracts for the native mood-icon popover overlay.

local mood_overlay = reqscript('dwarfui-mood-popover')

local MoodPopoverOverlay = mood_overlay.MoodPopoverOverlay
local state

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
---@return table
local function mount_overlay()
    return ds.mount(MoodPopoverOverlay, {
        initial_pause=false,
        viewport={width=80, height=25},
        hover_provider=function() return state.hover end,
        mouse_provider=function() return state.mouse_x, state.mouse_y end,
        snapshot_provider=function(descriptor)
            return state.rows[descriptor.hover_index] or {}
        end,
        active_provider=function() return state.active end,
        refresh_interval=1,
    })
end

---Selects one injected native mood icon at a deterministic screen position.
---@param hover_index integer
---@param x integer
---@param y integer
local function select_mood(hover_index, x, y)
    state.hover = df.main_hover_instruction['INFO_STRESSED_' .. hover_index]
    state.mouse_x, state.mouse_y = x, y
    ds.wait_frames(1)
end

---Returns the mounted reusable popover and its stable controls.
---@return table, table, table
local function popover_controls()
    return ds.get('mood_popover'), ds.get('mood_popover/header'),
        ds.get('mood_popover/list')
end

describe('live mood popover overlay component', function()
    local root

    before_each(function()
        state = {active=true, hover=nil, mouse_x=nil, mouse_y=nil, rows={}}
        for index=0,6 do
            state.rows[index] = rows_for({
                hover_index=index,
                label=({'Ecstatic', 'Happy', 'Pleased', 'Content',
                    'Displeased', 'Unhappy', 'Miserable'})[index + 1],
            })
        end
        root = mount_overlay()
    end)

    it('renders every injected native mood heading, count, and row set',
            function()
        local labels = {'Ecstatic', 'Happy', 'Pleased', 'Content',
            'Displeased', 'Unhappy', 'Miserable'}
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
        for _=1,20 do root:input('STANDARDSCROLL_DOWN') end
        assert.equals(20 - root:raw().popover.visible_rows + 1,
            root:raw().popover.scroll_top)
        assert.equals(root:raw().popover.scroll_top, list:raw().page_top)
        assert.equals('Content Unit 20', list:raw().choices[20].text)

        state.mouse_x, state.mouse_y = 0, 0
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
        assert.equals('Pleased (0)', header:text())
        assert.is_false(list:inspect().visible)

        ds.viewport(30, 10)
        frame = root:raw().popover.frame_global
        assert.is_true(frame.x >= 0 and frame.x + frame.w <= 30)
        assert.is_true(frame.y >= 0 and frame.y + frame.h <= 10)

        state.mouse_x = nil
        ds.wait_frames(1)
        assert.is_nil(root:raw().selected_descriptor)
        assert.is_false(popover:inspect().visible)
    end)

    it('cleans state on unmount and begins a remount without stale rows',
            function()
        select_mood(4, 10, 3)
        local first = root:raw()
        assert.equals('Displeased', first.selected_descriptor.label)
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
