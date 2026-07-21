-- Live component contracts for tooltip behavior inside an overlay widget.

local gui = require('gui')
local widgets = require('gui.widgets')
local overlay = require('plugins.overlay')
local tooltip = reqscript('dwarfui/tooltip')

---@class tests.TooltipOverlayComponent: plugins.overlay.OverlayWidget
local TooltipOverlayComponent = defclass(nil, overlay.OverlayWidget)
TooltipOverlayComponent.ATTRS{
    default_pos={x=1, y=1},
    frame={w=8, h=4},
    viewscreens='dwarfmode',
}

---Builds a clipped target with a root-external tooltip renderer.
function TooltipOverlayComponent:init()
    self.tooltip_target = widgets.Label{
        view_id='tooltip_target',
        frame={l=0, t=0, r=0, b=0},
        text=' ',
        tooltip='Automation overlay tooltip outside its narrow root.',
    }
    self.tooltip_renderer = tooltip.TooltipRenderer{}
    self.tooltip_renderer.parent_view = self
    self.tooltip_agent = tooltip.TooltipAgent.new(
        self, self.tooltip_renderer)
    self:addviews{self.tooltip_target}
end

---Updates tooltip state from the same pointer sample as this render.
function TooltipOverlayComponent:onRenderFrame()
    self.tooltip_agent:update()
end

---Renders the overlay and then its deliberately unclipped tooltip layer.
---@param dc gui.Painter
function TooltipOverlayComponent:render(dc)
    TooltipOverlayComponent.super.render(self, dc)
    if self.tooltip_renderer.visible then
        self.tooltip_renderer:render(gui.Painter.new())
    end
end

describe('live tooltip overlay component', function()
    it('mounts directly and presents outside the clipped overlay root',
            function()
        local root = ds.mount(TooltipOverlayComponent, {
            initial_pause=false,
            overlay_position={x=1, y=1},
        })
        local target = ds.get('tooltip_target')
        target:move_pointer('top_left')
        ds.await('overlay component tooltip visible', function()
            return root:raw().tooltip_renderer.visible
        end)

        local component = root:raw()
        assert.equals(target:raw().tooltip,
            component.tooltip_renderer.tooltip_text)
        assert.is_true(component.tooltip_renderer.frame.l +
            component.tooltip_renderer.frame.w - 1 >
            component.frame_body.clip_x2)
    end)
end)
