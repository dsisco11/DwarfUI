# DwarfUI

DwarfUI is a DFHack mod that provides reusable UI infrastructure and its own
user-facing interface enhancements.

The shared public Lua namespace is installed under `scripts_modinstalled/dwarfui/`.
The tooltip port reserves these downstream module paths:

- `dwarfui/text`
- `dwarfui/widget_extensions`
- `dwarfui/pointer`
- `dwarfui/tooltip`
- `dwarfui/tooltip_registration`

All modules use DFHack's `--@ module=true` script-environment contract and are
loaded with `reqscript()`. `dwarfui/text` provides
standalone text wrapping, and importing `dwarfui/widget_extensions` installs
the declarative tooltip and pointer attributes on DFHack's native widget
classes. `dwarfui/pointer` provides isolated per-root pointer contexts and
generic target/pass/block/none dispatch. `dwarfui/tooltip` provides the plain-
widget `TooltipRenderer`, the stable singleton registration facade, and the
explicit per-root `TooltipAgent` available to unusual screen and overlay hosts.

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

## Automatic tooltip registration

The stable high-level API is exposed by `dwarfui/tooltip`:

```lua
local tooltip = reqscript('dwarfui/tooltip')

local label = widgets.Label{
    text='Hover me',
    tooltip='Static tooltip text',
}
tooltip.register(label)
```

Registration may happen before or after attachment. It is idempotent and uses
weak keys, so ordinary widget lifetime does not require explicit cleanup.
`tooltip.unregister(label)` is available when immediate removal is useful.

One transparent top-level `ZScreen` owns exactly one renderer and displays at
most one tooltip process-wide. It does not modify consumer roots or intercept
their methods. Normal screens and enabled, focus-matching overlays are
supported. The explicit `TooltipRenderer` and `TooltipAgent` API above remains
available as a low-level path for unusual hosts.

## Live automation

DwarfUI consumes [DwarfSpec](https://github.com/dsisco11/DwarfSpec) as the
test-only dependency declared in `dwarfui-0.1.0-1.rockspec`. DwarfSpec is not
part of the DwarfUI mod payload. Install the dependency into the development
rock tree, start Dwarf Fortress with DFHack, and run the product specs through
the installed command:

```powershell
luarocks test --prepare dwarfui-0.1.0-1.rockspec
dwarfspec run tests/tooltip/tooltip_spec.ds.lua
dwarfspec run tests/tooltip/tooltip_overlay_spec.ds.lua
```

The specs, configuration command, and fixtures under `tests/` are
DwarfUI-owned consumer files. Test discovery, Busted hosting, live interaction,
cleanup, and reporting are supplied by the installed DwarfSpec package. See
DwarfSpec's writing-tests, configuration, and command-line documentation for
the framework contracts.
