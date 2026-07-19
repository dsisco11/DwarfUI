# DwarfUI

DwarfUI is a DFHack mod that provides reusable UI infrastructure and its own
user-facing interface enhancements.

The shared public Lua namespace is installed under `scripts_modinstalled/dwarfui/`.
The tooltip port reserves these downstream module paths:

- `dwarfui/text`
- `dwarfui/widget_extensions`
- `dwarfui/pointer`
- `dwarfui/tooltip`

All modules expose stable return-table contracts. `dwarfui/text` provides
standalone text wrapping, and importing `dwarfui/widget_extensions` installs
the declarative tooltip and pointer attributes on DFHack's native widget
classes. `dwarfui/pointer` provides isolated per-root pointer contexts and
generic target/pass/block/none dispatch. `dwarfui/tooltip` provides the plain-
widget `TooltipRenderer` and explicit per-root `TooltipAgent` used by
screen and overlay hosts.

## Explicit tooltip integration

The parity API intentionally requires each independently rendered root to own
one renderer and one agent. The screen and overlay recipes differ because an
overlay's ordinary subviews are clipped to its panel, while its tooltip must be
able to extend across the screen. Keep these steps explicit until the later
registration-API evaluation proves that DwarfUI can safely own them.

### `gui.ZScreen` host

Construct the tooltip facade before tooltip-bearing content, add the renderer
after ordinary content, and update its agent before the inherited render pass.
Subview insertion order then renders the tooltip above the screen content.

```lua
local gui = require('gui')
local widgets = require('gui.widgets')
local tooltip = reqscript('dwarfui/tooltip')

TooltipScreen = defclass(TooltipScreen, gui.ZScreen)

function TooltipScreen:init()
    self.content = widgets.Window{
        frame={l=2, t=2, w=30, h=8},
        subviews={
            widgets.Label{
                frame={l=1, t=1},
                text='Hover me',
                tooltip='Static tooltip text',
            },
        },
    }
    self.tooltip_renderer = tooltip.TooltipRenderer{}
    self:addviews{self.content, self.tooltip_renderer}
    self.tooltip_agent = tooltip.TooltipAgent.new(
        self, self.tooltip_renderer)
end

function TooltipScreen:onRender()
    self.tooltip_agent:update()
    TooltipScreen.super.onRender(self)
end
```

### `overlay.OverlayWidget` host

Do not add the renderer to the overlay's subviews. Update the agent in
`onRenderFrame()`, let the normal overlay render complete, and then render the
tooltip with the original parent painter. Setting `parent_view` preserves
invalidation without putting the renderer into the clipped subview traversal.

```lua
local widgets = require('gui.widgets')
local overlay = require('plugins.overlay')
local tooltip = reqscript('dwarfui/tooltip')

TooltipOverlay = defclass(TooltipOverlay, overlay.OverlayWidget)

function TooltipOverlay:init()
    self.content = widgets.Panel{
        frame={l=0, t=0, w=20, h=6},
        subviews={
            widgets.Label{
                frame={l=1, t=1},
                text='Hover me',
                tooltip='Overlay tooltip text',
            },
        },
    }
    self:addviews{self.content}
    self.tooltip_renderer = tooltip.TooltipRenderer{}
    self.tooltip_renderer.parent_view = self
    self.tooltip_agent = tooltip.TooltipAgent.new(
        self, self.tooltip_renderer)
end

function TooltipOverlay:onRenderFrame(dc, rect)
    self.tooltip_agent:update()
    TooltipOverlay.super.onRenderFrame(self, dc, rect)
end

function TooltipOverlay:render(dc)
    TooltipOverlay.super.render(self, dc)
    if self.tooltip_renderer.visible then
        self.tooltip_renderer:render(dc)
    end
end
```

Each screen or overlay instance must construct its own agent and renderer.
Never share a `TooltipAgent`, `PointerContext`, or `TooltipRenderer` between
independently rendered roots.
