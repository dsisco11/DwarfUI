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

Transport selection is limited to the registered target's currently presented
root. A target in a native `OverlayWidget` uses the process-wide wrapper around
DFHack's exported overlay-render function. A target in the current foreground
Lua screen uses an on-demand wrapper around that root instance's callable
`onRender()` method. Covered Lua screens and roots that match neither supported
surface do not paint a tooltip.

DFHack does not expose an engine-level post-compositor callback to Lua. These
hooks therefore guarantee final ordering only within the supported native
overlay render pass or wrapped foreground Lua screen. Content painted later by
an unrelated engine or extension hook can still cover the tooltip. If another
extension wraps DwarfUI's active render function, DwarfUI remains in that
predecessor chain without taking ownership of the extension's exported
function slot; this preserves the other extension's exact cleanup contract.
A wrapper that performs post-render painting can explicitly mark itself
reorderable through the render-hook manager when it wants DwarfUI to repair
above that work.

## Context menus

The registration-driven context-menu API is exposed by
`dwarfui/context_menu/api`. A widget registration opens at the current
interface-cell pointer position when the registered widget wins pointer hit
testing:

```lua
local context_menu = reqscript('dwarfui/context_menu/api')

local action_label = widgets.Label{text='Right-click me'}
context_menu.register(action_label, {
    title='Label actions',
    fg=COLOR_WHITE,
    bg=COLOR_BLACK,
    entries={
        {
            label='Inspect',
            on_select=function(context)
                print(('widget registration %d selected'):format(
                    context.registration_identity))
            end,
        },
        {
            label='Remove',
            fg=COLOR_LIGHTRED,
            on_select=function(context)
                context.source.visible = false
            end,
        },
    },
})
```

`register(widget, definition)` creates a weak registration or replaces the
definition of an existing registration while retaining its identity and
precedence. `update(widget, definition)` returns `false` for an unknown widget,
and `unregister(widget)` removes it immediately. A widget must be attached,
visible, enabled, and part of the currently presented eligible root to open.
The captured screen-position anchor remains fixed while the menu is open.

Exact map tiles use disposable handles:

```lua
local route_menu = context_menu.register_map_tile{
    owner=route_overlay,
    pos={x=stop.pos.x, y=stop.pos.y, z=stop.pos.z},
    definition={
        title='Route stop',
        entries={{
            label='Move stop',
            on_select=function(context)
                begin_move(context.map_position)
            end,
        }},
    },
}

context_menu.update_map_tile(route_menu, {
    pos={x=new_pos.x, y=new_pos.y, z=new_pos.z},
    definition=updated_definition,
})
context_menu.unregister_map_tile(route_menu)
```

Map positions are copied signed 16-bit integer `x`, `y`, and `z` coordinates.
Both `pos` and `definition` are required by the atomic update operation. A map
registration is weakly owned by both its handle and `owner`; retaining neither
does not keep the registration alive. Its owner must resolve to an attached,
visible, enabled root on the current viewscreen. If several eligible
registrations occupy the same exact tile, the most recently registered one
wins. Updating a registration preserves that original precedence.

A definition contains an optional non-empty `title`, optional menu `fg` and
`bg`, and a non-empty `entries` array. Each entry requires a non-empty `label`
and an `on_select` Lua function, and may specify its own `fg` and `bg`.
Colors are integer display colors from `COLOR_BLACK` through `COLOR_WHITE`;
pens, `COLOR_RESET`, and other representations are rejected. Each missing
entry color falls back independently to the menu color, then to
`COLOR_WHITE` foreground or `COLOR_BLACK` background. Menu colors paint the
Window frame, title, and body. Entry colors paint their complete rows, with a
readable active-row treatment for hover and keyboard selection. Definitions
are validated and copied at registration or update time, and an opening takes
another snapshot.

The `on_select(context)` value contains `target_kind`, `anchor_kind`,
`registration_identity`, a copied opening `screen_position`, `source`,
`source_root`, and optional `owner`. Map selections also receive a copied
`map_position`. The menu closes before the handler is invoked. Selection and
an outside left-click both close and consume their complete input event; Escape
or a second right-click also closes and consumes. Other input is delegated.
There is no public programmatic open or replacement operation, and
right-clicking while a menu is already open only closes it.

An open map menu reprojects its copied tile before every render, so camera
movement keeps the Window attached to the tile. It closes if the tile leaves
the visible viewport, changes z-level relative to the view, or its registration
or owner becomes invalid. Reload, DwarfUI teardown, and world unload close the
active menu and discard every context-menu registration. Consumers must
register again afterward.

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
.\tools\Run-AutomationTests.ps1 tests/minecart_route/minecart_route_tooltip.ds.lua
.\tools\Run-AutomationTests.ps1 tests/tooltip/tooltip_screen_final_render.ds.lua
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
