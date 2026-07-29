# DwarfUI

DwarfUI is a DFHack mod that provides reusable UI infrastructure and its own
user-facing interface enhancements.

The shared public Lua namespace is installed under `scripts_modinstalled/dwarfui/`.
The tooltip port reserves these downstream module paths:

- `dwarfui/text`
- `dwarfui/widget_extensions`
- `dwarfui/pointer`
- `dwarfui/pointer_poller`
- `dwarfui/tooltip_target_detector`
- `dwarfui/tooltip_service`
- `dwarfui/tooltip_render_hook`
- `dwarfui/tooltip`
- `dwarfui/tooltip_registration`

All modules use DFHack's `--@ module=true` script-environment contract and are
loaded with `reqscript()`. `dwarfui/text` provides
standalone text wrapping, and importing `dwarfui/widget_extensions` installs
the declarative tooltip and pointer attributes on DFHack's native widget
classes. `dwarfui/pointer` provides isolated per-root pointer contexts and
generic target/pass/block/none dispatch. The remaining tooltip modules provide
process-wide weak registration, pointer polling, immutable tooltip intent, and
final rendering through reload-safe native-overlay and Lua-screen hooks.
`dwarfui/tooltip` is the stable public registration facade.

## Mood icon unit popover

DwarfUI includes a default-enabled `dwarfui-mood-popover` overlay for the
default fortress screen. Hover any of the seven native mood icons beside the
`Pop` counter in the top information bar to see every active citizen in that
mood category. The list is ordered by readable unit name and the panel stays
open while moving from the icon into the panel. The thin-bordered panel leaves
one clear row beneath the top information bar so it does not cover its edge.

For a list that exceeds the available height, point at the panel and use the
mouse wheel to scroll. The overlay leaves clicks, keyboard input, and wheel
events outside its list to Dwarf Fortress.

The overlay can be managed with DFHack's overlay command:

```text
overlay disable dwarfui-mood-popover.mood_popover
overlay enable dwarfui-mood-popover.mood_popover
```

The mood model and popover widget that support this feature are
project-internal implementation details in this release; their module paths
are not downstream API contracts.

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

Registration creates no screen, overlay widget, focus owner, input handler, or
renderer. A presentation-neutral poller publishes one immutable process-wide
intent. The presenter reads that intent and draws one tooltip after the owning
native overlay or foreground Lua screen has completed rendering. Lua-screen
support wraps only the root instance's effective `onRender()` method; it does
not add subviews or modify focus, input, logic, or screen configuration.

## Runtime validation and reload

Run `dwarfui` to load the registered module graph and validate each module's
public runtime contract. During development, run `dwarfui reload` to clear the
current module generation, rebuild it in dependency order, and have DFHack
rescan the mood-popover and unit-card overlays.

```text
dwarfui
dwarfui reload
```

The registry at `dwarfui/module_registry` is the authoritative manifest for
reload ordering. New DwarfUI modules must be added there with a representative
function or class contract.

## Live automation

DwarfUI consumes [DwarfSpec](https://github.com/dsisco11/DwarfSpec) as the
test-only dependency declared in `dwarfui.rockspec`. DwarfSpec is not
part of the DwarfUI mod payload. Install the dependency into the development
rock tree, start Dwarf Fortress with DFHack, and run the product specs through
the installed command:

```powershell
luarocks test --prepare dwarfui.rockspec
.\tools\Run-AutomationTests.ps1 tests/mood_popover/mood_popover.ds.lua
.\tools\Run-AutomationTests.ps1 tests/tooltip/tooltip.ds.lua
.\tools\Run-AutomationTests.ps1 tests/tooltip/tooltip_overlay.ds.lua
.\tools\Run-AutomationTests.ps1 tests/tooltip/tooltip_overlay_registration_integration.ds.lua
```

The component specs, registration source, and configuration under `tests/` are
DwarfUI-owned consumer files. Test discovery, Busted hosting, live interaction,
cleanup, and reporting are supplied by the installed DwarfSpec package. See
DwarfSpec's writing-tests, configuration, and command-line documentation for
the framework contracts.

Native-interaction claims require a borrowed native screen, public DwarfSpec
pointer or input commands, and observable production rendering or state.
Calling an internal widget callback directly is method or component coverage
and must not be presented as proof of native interaction. Tests mounted with
`ds.mount(...)` cover their test-owned fixture unless they separately attach to
and exercise the production native screen.
