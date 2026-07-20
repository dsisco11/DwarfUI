-- Test-owned screen that creates a real screen-stack transition.

local gui = require('gui')

---@class tests.TooltipCoverScreen: gui.ZScreen
local TooltipCoverScreen = defclass(nil, gui.ZScreen)
TooltipCoverScreen.ATTRS{
    initial_pause=false,
    pass_mouse_clicks=true,
}

---Initializes the live-render counter used by the automation driver.
function TooltipCoverScreen:init()
    self.render_generation = 0
end

---Records each real render of the covering screen.
function TooltipCoverScreen:onRender()
    TooltipCoverScreen.super.onRender(self)
    self.render_generation = self.render_generation + 1
end

local M = {}

---Creates one test-owned covering screen.
---@return table
function M.new()
    return TooltipCoverScreen{}
end

return M
