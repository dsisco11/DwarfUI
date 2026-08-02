# DwarfUI

DwarfUI is a DFHack feature and component library. It supplies feature-specific
overlays, widgets, commands, and workflows, and depends on DwarfUICore for its
shared UI runtime.

## Dependency installation

Install the DwarfUICore package before DwarfUI. DwarfUI requires
`dwarfuicore >= 0.2.0`; neither the source tree nor the package contains a
second copy of DwarfUICore.

The DwarfUI feature tests require an explicit Core source checkout:

```powershell
.\tools\Run-UnitTests.ps1 -DwarfUICoreSource ..\DwarfUICore
```

`DWARFUICORE_SOURCE` is the equivalent environment variable. To validate the
package ordering and installed script resolution in an isolated mod tree, run:

```powershell
.\tools\Setup-CoreIntegration.ps1 `
    -DwarfUICoreSource ..\DwarfUICore `
    -DwarfUICorePackage <DwarfUICorePackage> `
    -DwarfUIPackage <DwarfUIPackage>
```

## Ownership boundary

DwarfUI owns its feature-specific behavior, including the mood popover,
hotkeys, minecart route markers, unit cards, asset-button hover rails, and
their integration with Dwarf Fortress screens.

DwarfUICore owns reusable tooltip, context-menu, pointer, registration, and
presentation infrastructure. DwarfUI uses those systems where a feature needs
them. For example, minecart route markers obtain their tooltip behavior from
DwarfUICore while DwarfUI owns the marker feature and its route actions.

All DwarfUI entrypoints share exact contract major 1 through the stable
`dwarfui` namespace:

```lua
local services = reqscript('dwarfui/services')
local tooltip = services.TooltipService
local context_menu = services.ContextMenuService
```

Independent plugins acquire their own namespace directly from
`reqscript('dwarfuicore/services')`; they do not use DwarfUI's binding.

## Reload behavior

`dwarfui reload` explicitly clears and rebuilds only the `dwarfui` tooltip
and context-menu namespaces and DwarfUI-owned modules. It does not reload
DwarfUICore or clear registrations owned by another consumer namespace.

## Feature use

The mood popover and minecart route marker features retain their normal DwarfUI
commands and screen integration. The minecart marker's `Zoom to this stop`
interaction remains a DwarfUI feature; only its shared tooltip infrastructure
is supplied by DwarfUICore.

Run local checks from this repository root:

```powershell
.\tools\Run-UnitTests.ps1 -DwarfUICoreSource ..\DwarfUICore
.\tools\Check-LuaSyntax.ps1 -IncludeTests
.\tools\Publish.ps1
```

Native Dwarf Fortress verification is a separate workflow from these source
and package checks.

## Service-provider contract

DwarfUICore owns the provider contract and the one process-wide runtime.
DwarfUI is a namespace-bound consumer and performs explicit namespace cleanup
for reload and teardown. API objects do not own registrations, so collecting a
cached service object is not a cleanup mechanism.

Migrating independent consumer plugins remains separate work; no independent
plugin is migrated through DwarfUI.
