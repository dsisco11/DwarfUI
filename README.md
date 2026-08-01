# DwarfUI

DwarfUI is a DFHack feature and component library. It supplies feature-specific
overlays, widgets, commands, and workflows, and depends on DwarfUICore for its
shared UI runtime.

## Dependency installation

Install the DwarfUICore package before DwarfUI. DwarfUI currently requires
`dwarfuicore >= 0.1.0`; neither the source tree nor the package contains a
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

The old `dwarfui/tooltip/api` and `dwarfui/context_menu/api` module paths no
longer exist. Consumers that need the current extracted compatibility APIs must
load DwarfUICore directly:

```lua
local tooltip = reqscript('dwarfuicore/tooltip/api')
local context_menu = reqscript('dwarfuicore/context_menu/api')
```

## Reload behavior

`dwarfui reload` is an explicit development command for DwarfUI-owned modules.
It does not reload DwarfUICore. Normal DwarfUI and DwarfUICore module loading
does not perform a development reload or clear script environments.

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

## Future service-provider contract

The proposed service-provider API is owned by
[DwarfUICore](https://github.com/dsisco11/DwarfUICore/blob/main/Docs/service-provider-api-proposal.md).
It is not implemented by the repository split: provider classes, consumer
namespaces, composite identities, exact contract-version negotiation,
immutable handles, and collision rules are all future design work. DwarfUI
does not maintain a second copy of that proposal.

Migrating independent consumer plugins to DwarfUICore is separate future work;
no consumer plugins were changed as part of this split.
