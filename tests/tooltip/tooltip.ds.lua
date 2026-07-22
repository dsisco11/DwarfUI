-- Live product contracts for the singleton tooltip service.

local gui = require('gui')
local widgets = require('gui.widgets')
local tooltip = reqscript('dwarfui/tooltip')

---@class tests.TooltipCoverScreen: gui.ZScreen
local TooltipCoverScreen = defclass(nil, gui.ZScreen)
TooltipCoverScreen.ATTRS{initial_pause=false, pass_mouse_clicks=true}

---@class tests.TooltipScreen: gui.ZScreen
local TooltipScreen = defclass(nil, gui.ZScreen)
TooltipScreen.ATTRS{
    initial_pause=false,
    pass_mouse_clicks=true,
    blocker_visible=false,
}

---Builds a normal-screen target and an optionally visible modal blocker.
function TooltipScreen:init()
    self.last_key = nil
    self.target = widgets.Label{
        view_id='tooltip_target',
        frame={l=2, t=2, w=24, h=1},
        text='Automation tooltip target',
        tooltip='Automation static tooltip',
    }
    self.target.on_pointer_update = function(target, x, y)
        target.tooltip = ('Automation dynamic tooltip %d,%d'):format(x, y)
    end
    self.blocker = widgets.Window{
        view_id='tooltip_blocker',
        frame={l=1, t=1, w=28, h=4},
        title='Automation blocker',
        visible=self.blocker_visible,
    }
    self:addviews{self.target, self.blocker}
end

---Records a forwarded synthetic key without consuming unrelated input.
---@param keys table
---@return boolean
function TooltipScreen:onInput(keys)
    if keys.CUSTOM_A then
        self.last_key = 'CUSTOM_A'
        return true
    end
    return TooltipScreen.super.onInput(self, keys)
end

---Creates a temporary native screen above the singleton service.
function TooltipScreen:show_cover()
    self.cover = TooltipCoverScreen{}
    self.cover:show()
end

---Dismisses the temporary native screen when it is still active.
function TooltipScreen:dismiss_cover()
    if self.cover and self.cover:isActive() then self.cover:dismiss() end
end

---Releases product registrations and child screens owned by this component.
function TooltipScreen:onDismiss()
    self:dismiss_cover()
    tooltip.unregister(self.target)
    TooltipScreen.super.onDismiss(self)
end

---Returns the product diagnostics registered in tests/dwarfspec/config.lua.
---@return table
local function diagnostics()
    return ds.tooltip_state()
end

---Recreates the service for an attached DwarfSpec subject.
---@param target table
local function restart_service_for_target(target)
    local view = target:raw()
    tooltip.unregister(view)
    assert.is_true(tooltip.register(view))
    ds.wait_frames(2)
end

describe('live singleton tooltip service', function()
    local root
    local screen

    before_each(function()
        root = ds.mount(TooltipScreen, {initial_pause=false})
        screen = root:raw()
    end)

    it('targets normal screens and presents dynamic text after real renders',
            function()
        local target = ds.get('tooltip_target')
        local body = assert(target:inspect().body)
        local mouse_x = math.floor((body.x1 + body.x2) / 2)
        local mouse_y = math.floor((body.y1 + body.y2) / 2)
        target:move_pointer()
        restart_service_for_target(target)

        local state = diagnostics()
        assert.equals(target:raw(), state.target)
        assert.is_true(state.screen.renderer.visible)
        assert.equals(('Automation dynamic tooltip %d,%d'):format(
            mouse_x - target:raw().frame_body.x1,
            mouse_y - target:raw().frame_body.y1),
            state.screen.renderer.tooltip_text)
        assert.equals(state.screen.frame_parent_rect,
            state.screen.renderer.frame_parent_rect)
    end)

    it('blocks targets covered by a modal view through real rendering',
            function()
        ds.unmount()
        root = ds.mount(TooltipScreen, {
            initial_pause=false,
            blocker_visible=true,
        })
        screen = root:raw()
        local target = ds.get('tooltip_target')
        target:move_pointer()
        restart_service_for_target(target)
        assert.is_nil(diagnostics().target)
        assert.is_false(diagnostics().screen.renderer.visible)
    end)

    it('recovers z-order and forwards input over a newly opened screen',
            function()
        local target = ds.get('tooltip_target')
        target:move_pointer()
        restart_service_for_target(target)
        local state = diagnostics()
        assert.equals(target:raw(), state.target)
        root:input('CUSTOM_A')
        assert.equals('CUSTOM_A', screen.last_key)
        assert.is_false(state.screen:isMouseOver())

        screen:show_cover()
        ds.wait_frames(2)
        assert.is_true(state.screen:hasFocus())
        screen:dismiss_cover()
    end)
end)
