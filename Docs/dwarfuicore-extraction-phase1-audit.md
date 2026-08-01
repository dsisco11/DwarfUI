# DwarfUICore Extraction Phase 1 Audit

## Scope

This audit freezes the behavior-preserving boundary for extracting DwarfUICore
from DwarfUI. It inventories current ownership and records baseline evidence.
It does not implement the proposed service-provider architecture, fix existing
defects, create the sibling repository, or modify independent consumers.

Captured on 2026-07-31 in `D:\CODE\DFHack\DwarfUI`.

## Repository and runtime baseline

| Item | Baseline |
| --- | --- |
| Repository root | `D:/CODE/DFHack/DwarfUI` |
| Branch | `context-menu-system` |
| Upstream | `origin/context-menu-system` |
| Upstream relation | Ahead 1, behind 0 |
| HEAD | `dacc9c767855d5b05d5566757e161e966729dc87` |
| Initial worktree | Clean |
| Initial index | Clean |
| Stash or commit performed | No |
| Mod ID | `dwarfui` |
| Source package version | `0.1.0` (`NUMERIC_VERSION:1`) |
| Resolved live root script | `D:/CODE/DFHack/DwarfUI/src/scripts_modinstalled/dwarfui.lua` |
| Lua toolchain | Lua 5.4.6 |
| DwarfSpec | 0.2.1 |

The resolved live script is repository source, not the expanded package under
`dist/` or a separately installed Workshop copy. Repository, package, and live
evidence remain distinct throughout the extraction.

## Inventory summary

| Category | Count |
| --- | ---: |
| Production Lua files | 50 |
| Proposed DwarfUICore-owned production modules | 32 |
| DwarfUI-retained production modules | 18 |
| Unit spec files | 50 |
| Live DwarfSpec files | 13 |
| All test/support Lua files | 73 |
| Project tool scripts | 8 |
| Existing documentation/planning files at capture | 7 |

## Production ownership

### DwarfUICore-owned foundations

These modules move and are renamed under `dwarfuicore/`:

- `dwarfui/class.lua`
- `dwarfui/text.lua`
- `dwarfui/map_projection.lua`
- `dwarfui/pointer.lua`
- `dwarfui/pointer_poller.lua`
- `dwarfui/view_root_resolver.lua`
- `dwarfui/widget_extensions.lua`
- `dwarfui/utils/function_chain.lua`
- `dwarfui/utils/immutable_enum.lua`
- `dwarfui/utils/numbers.lua`

### DwarfUICore-owned tooltip system

The complete directory moves and is renamed:

- `dwarfui/tooltip/api.lua`
- `dwarfui/tooltip/map_target.lua`
- `dwarfui/tooltip/presenter.lua`
- `dwarfui/tooltip/registration.lua`
- `dwarfui/tooltip/render_hook.lua`
- `dwarfui/tooltip/renderer.lua`
- `dwarfui/tooltip/runtime.lua`
- `dwarfui/tooltip/service.lua`
- `dwarfui/tooltip/target_detector.lua`
- `dwarfui/tooltip/target.lua`

### DwarfUICore-owned context-menu system

The complete directory moves and is renamed:

- `dwarfui/context_menu/api.lua`
- `dwarfui/context_menu/definition.lua`
- `dwarfui/context_menu/input_hook.lua`
- `dwarfui/context_menu/input_sample.lua`
- `dwarfui/context_menu/map_target.lua`
- `dwarfui/context_menu/registration.lua`
- `dwarfui/context_menu/renderer.lua`
- `dwarfui/context_menu/root_discovery.lua`
- `dwarfui/context_menu/screen.lua`
- `dwarfui/context_menu/service.lua`
- `dwarfui/context_menu/target_detector.lua`
- `dwarfui/context_menu/target.lua`

### DwarfUI-retained production modules

DwarfUI keeps its feature entrypoints, components, and models:

- `dwarfui-minecart-route-markers.lua`
- `dwarfui-mood-popover.lua`
- `dwarfui-ui-hotkeys.lua`
- `dwarfui-unit-card-task-details.lua`
- `dwarfui.lua`
- `dwarfui/module_registry.lua`
- `dwarfui/hotkeys/geometry.lua`
- `dwarfui/hotkeys/layout_provider.lua`
- `dwarfui/hotkeys/model.lua`
- `dwarfui/hotkeys/overlay.lua`
- `dwarfui/hotkeys/groups/fortress_main.lua`
- `dwarfui/minecart_route.lua`
- `dwarfui/mood_popover.lua`
- `dwarfui/popover.lua`
- `dwarfui/ui_hotkeys.lua`
- `dwarfui/unit_card_task.lua`
- `dwarfui/widgets/asset_button.lua`
- `dwarfui/widgets/hover_action_rail.lua`

`dwarfui.lua` and `dwarfui/module_registry.lua` remain DwarfUI files, but their
current shared-runtime validation and reload logic is source material for new
DwarfUICore-owned equivalents. The final registries are separate; the current
registry is not moved wholesale.

## Transitive production dependency graph

### Tooltip root

```text
dwarfui/tooltip/api
|-- dwarfui/tooltip/registration
|   |-- dwarfui/tooltip/service
|   |   `-- dwarfui/tooltip/target
|   |-- dwarfui/pointer_poller
|   |-- dwarfui/tooltip/target_detector
|   |   |-- dwarfui/pointer
|   |   |   `-- dwarfui/utils/immutable_enum
|   |   |-- dwarfui/tooltip/target
|   |   `-- dwarfui/view_root_resolver
|   |       `-- dwarfui/class
|   |-- dwarfui/tooltip/map_target
|   |   |-- dwarfui/view_root_resolver
|   |   `-- dwarfui/tooltip/target
|   `-- dwarfui/tooltip/target
`-- dwarfui/tooltip/runtime
    |-- dwarfui/tooltip/presenter
    |   `-- dwarfui/class
    |-- dwarfui/tooltip/renderer
    |   |-- dwarfui/pointer
    |   |-- dwarfui/widget_extensions
    |   |   `-- dwarfui/pointer
    |   `-- dwarfui/text
    |-- dwarfui/tooltip/service
    `-- dwarfui/tooltip/render_hook
        `-- dwarfui/utils/function_chain
```

### Context-menu root

```text
dwarfui/context_menu/api
|-- dwarfui/context_menu/registration
|   |-- dwarfui/context_menu/definition
|   |   `-- dwarfui/utils/numbers
|   |-- dwarfui/context_menu/map_target
|   |   |-- dwarfui/context_menu/definition
|   |   |-- dwarfui/context_menu/target
|   |   |-- dwarfui/utils/numbers
|   |   `-- dwarfui/view_root_resolver
|   |-- dwarfui/context_menu/root_discovery
|   |-- dwarfui/context_menu/target
|   |   |-- dwarfui/context_menu/definition
|   |   |-- dwarfui/utils/immutable_enum
|   |   `-- dwarfui/utils/numbers
|   `-- dwarfui/view_root_resolver
|       `-- dwarfui/class
|-- dwarfui/context_menu/screen
|   |-- dwarfui/map_projection
|   |-- dwarfui/context_menu/renderer
|   |-- dwarfui/context_menu/service
|   `-- dwarfui/context_menu/target
`-- dwarfui/context_menu/service
    |-- dwarfui/context_menu/input_hook
    |   |-- dwarfui/utils/function_chain
    |   `-- dwarfui/utils/immutable_enum
    |-- dwarfui/context_menu/input_sample
    |   `-- dwarfui/utils/numbers
    |-- dwarfui/context_menu/registration
    |-- dwarfui/context_menu/target_detector
    |   |-- dwarfui/utils/immutable_enum
    |   |-- dwarfui/pointer
    |   `-- dwarfui/context_menu/target
    |-- dwarfui/context_menu/target
    `-- dwarfui/utils/numbers
```

No DwarfUICore candidate depends on a DwarfUI-retained feature module.
DwarfUI-retained `AssetButton`, `HoverActionRail`, minecart, and hotkey modules
currently depend on foundations that will move, so those imports change during
the DwarfUI cutover.

## Test, fixture, tool, and document ownership

### Move to DwarfUICore

- All unit specs and support under `tests/tooltip/`.
- All unit specs and support under `tests/context_menu/`.
- Generic live specs under `tests/tooltip/` and `tests/context_menu/`.
- `class.spec.lua`, `text.spec.lua`, `map_projection.spec.lua`,
  `pointer.spec.lua`, `pointer_poller.spec.lua`, and
  `widget_extensions.spec.lua`.
- `tests/utils/immutable_enum.spec.lua` and `tests/utils/numbers.spec.lua`.
- `Docs/tooltip-registration-decision.md`.
- The service-provider proposal after the physical split is complete.

### Retain in DwarfUI

- Asset-button, hover-action-rail, hotkey, minecart, mood, popover,
  UI-hotkey, unit-card, and feature-overlay unit specs.
- Minecart and mood live specs and their feature-owned support.
- `Docs/hover-action-rail-proposal.md`, `Docs/project.todo`, and reusable-hotkey
  documents.
- DwarfUI feature and package documentation.

### Split or copy as repository-local infrastructure

- `tests/module_registry.spec.lua` becomes separate registry tests.
- `tests/package_contract.spec.lua` becomes separate package tests.
- `tests/infrastructure_smoke.spec.lua` and `tests/dwarfspec_config.spec.lua`
  are adapted for both repositories.
- `tests/run.lua`, `tests/support/module_loader.lua`,
  `tests/support/repo_root.lua`, and the necessary widget harness are copied as
  test-only infrastructure where required.
- `.busted`, `.luarc.json`, DwarfSpec configuration, and `tests/README.md` are
  made repository-specific.
- All eight `tools/` scripts are copied and renamed/configured so each project
  builds, tests, publishes, and verifies itself independently.
- Generated `tests/.test-results/` data is evidence, not source to transplant.

No independent consumer plugin is in the extraction inventory, and none is to
be edited by this task.

## External dependencies retained

DwarfUICore continues to depend on DFHack-provided modules and globals rather
than copying them:

- `gui`
- `gui.dwarfmode`
- `gui.widgets`
- `plugins.overlay`
- DFHack globals including `df`, `dfhack`, `defclass`, and `DEFAULT_NIL`

Project tooling retains Lua 5.3-or-newer compatibility, Lua 5.4.6 baseline
syntax evidence, Busted for unit tests, and DwarfSpec 0.2.1 for live tests.

## Behavior-preservation contract

The repository split preserves:

- the current tooltip and context-menu operations and return behavior;
- existing singleton, registration, weak-lifetime, polling, hook, presentation,
  input, error-containment, diagnostics, and explicit reload semantics;
- current widget and map registration identities;
- current target eligibility and ordering;
- current overlay and feature behavior; and
- normal initialization without development reload or environment clearing.

Approved changes are limited to repository ownership, project metadata,
internal module paths, LuaDoc ownership names, process-state root ownership,
separate registries, separate packages, and the DwarfUI dependency direction.

## Explicit architecture deferrals

The following belong to the unfinalized DwarfUICore service-provider proposal
and must not be introduced during the split:

- `dwarfuicore.services` provider exports;
- `ServiceProvider:new(contractVersion, consumerNamespace)`;
- public service contract-major negotiation or multiple-major adapters;
- consumer namespace validation, reservation, state, or cleanup;
- namespace-scoped widget and map identities;
- composite identities containing generation, service, contract, and namespace;
- immutable namespace-bound service API objects;
- provider-owned health manifests or atomic facade acquisition;
- new stale API-object or foreign-handle rules;
- newest-namespace tooltip arbitration;
- cross-namespace context-menu composition;
- new public diagnostics, error transport, or cleanup methods;
- migration of independent consumer plugins; and
- a `dwarfuicore-service-provider.todo` implementation checklist.

Possible refactors, cleanup, naming improvements, lifecycle repairs, and defect
fixes discovered while moving code are recorded separately unless strictly
required to preserve behavior across the new package boundary.

## Verification baseline

### Focused unit evidence

| Selection | Result |
| --- | --- |
| `tests/tooltip` | 98 successes, 0 failures, 0 errors, 0 pending |
| `tests/context_menu` | 103 successes, 0 failures, 0 errors, 0 pending |
| Shared Core candidate specs | 51 successes, 0 failures, 0 errors, 0 pending |
| `tests/tooltip/map_target.spec.lua` alone | 9 successes, 0 failures, 0 errors, 0 pending |

A noncanonical combined multi-path Busted invocation reproducibly reported 251
successes and one failure in the signed-16 tooltip map-key count assertion: it
observed one registration instead of five. The owning tooltip group, the exact
spec alone, and the complete suite all pass. This is recorded as an existing
invocation/order-sensitive test-isolation anomaly, not as successful combined
focused evidence and not as an extraction regression.

### Full unit evidence

`tools/Run-UnitTests.ps1` completed with 423 successes, 0 failures, 0 errors,
and 0 pending.

### Syntax evidence

`tools/Check-LuaSyntax.ps1 -Includetests` passed with Lua 5.4.6 for 50
production files and 73 test/support files.

### Package and archive evidence

`tools/Publish.ps1` passed its build, expanded-package comparison, zip-package
comparison, and overall package verification.

| Item | Result |
| --- | --- |
| Archive | `dist/DwarfUI-0.1.0.zip` |
| Expanded package | `dist/DwarfUI` |
| Archive files | 51 |
| Archive bytes | 113372 |
| Archive SHA-256 | `CCF0962422A471B7747F052C629B8B9D21259D6FD024DA58A6FCDAEC95DE0734` |
| `info.txt` | Present |
| `scripts_modinstalled/dwarfui.lua` | Present |
| Tooltip API | Present |
| Context-menu API | Present |
| Module registry | Present |

The archive hash records this generated baseline artifact; it is not a stable
cross-build identity because zip metadata can change between equivalent builds.

### Live evidence

DwarfSpec discovered four generic tooltip live specs and five generic
context-menu live specs. Before the first run, its service was unloaded. The
live root resolved to this repository checkout.

The tooltip group failed twice, including the requested retry after SoulSearch
was disabled:

| Run | Result | Cleanup |
| --- | --- | --- |
| Initial tooltip baseline | 2 successes, 0 failures, 4 errors | `cleanup_confirmed=false` |
| Retry after SoulSearch disable | 1 success, 1 failure, 4 errors | `cleanup_confirmed=false` |

Both runs failed during native rendering or overlay rescan at
`dwarfui/hotkeys/model.lua:120`, where the model calls
`provider_api.invoke(...)`. Live inspection confirmed that
`reqscript('dwarfui/hotkeys/layout_provider').invoke` is `nil` while resolving
the module from this checkout. Disabling SoulSearch did not change the failure.
The retry also reached a tooltip final-render assertion failure after the same
overlay problem had already affected the run.

The context-menu live group was not run after tooltip cleanup failed. Running a
second group while cleanup was unconfirmed would not provide attributable
baseline evidence.

After each failed run, DwarfSpec quarantined its executor. The documented
`recover-executor` command performed authoritative host verification and
successfully restored both runs. Final observed DwarfSpec state is:

```text
EXECUTOR idle
QUEUE 0
QUARANTINE none
```

Live tooltip and context-menu success therefore remains unavailable baseline
evidence. The local hotkey provider mismatch is a pre-existing blocker and is
not fixed by this audit.

## Phase 1 conclusion

The extraction boundary is complete and contains no unclassified production
module. Unit, syntax, package, archive, installed-resolution, and live outcomes
are recorded separately. DwarfUICore can be bootstrapped from the 32 identified
production modules and their owned tests without implementing the unfinished
service-provider design.
