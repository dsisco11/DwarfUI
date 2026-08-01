# DwarfUI Typed Service Provider Proposal

## Status

Proposed. This document defines a consumer-oriented public dependency contract.
It does not include production changes or consumer migrations.

## Decision summary

Make `dwarfui` the single public dependency entry point and expose a typed
provider class for each supported service:

```lua
local dwarfui = reqscript('dwarfui')
local tooltipService =
    dwarfui.services.TooltipServiceProvider:new()

tooltipService:register(widget)
```

Context menus use the parallel type:

```lua
local dwarfui = reqscript('dwarfui')
local contextMenuService =
    dwarfui.services.ContextMenuServiceProvider:new()

contextMenuService:register(widget, definition)
```

There is no global `dwarfui.get()` function, public service enum, string service
name, or consumer-visible registry. Choosing a provider class is the typed
service-selection operation.

Each `new()` call returns a lightweight provider-backed service handle. Handles
can be independent per consumer, but they all delegate to the same validated
process-wide DwarfUI runtime service and registration state.

## Why the provider is also the service handle

A conventional provider could require two operations:

```lua
local provider = dwarfui.services.TooltipServiceProvider:new()
local tooltipService = provider:get()
```

That extra `get()` adds no useful consumer decision. DwarfUI has one active
process-wide tooltip service and one active process-wide context-menu service.
Construction can therefore be the acquisition boundary: `new()` validates the
installation, initializes the service if necessary, and returns an object with
the public service methods.

The resulting object is not the internal `TooltipService` or
`ContextMenuService`. It is a narrow provider-backed handle that delegates only
documented consumer operations. Internal lifecycle, mediation, presentation,
hook, and shutdown operations remain inaccessible.

## Root public contract

The root module exports a `services` namespace containing provider types:

```lua
---@class dwarfui.Services
---@field TooltipServiceProvider dwarfui.TooltipServiceProviderClass
---@field ContextMenuServiceProvider dwarfui.ContextMenuServiceProviderClass

---@type dwarfui.Services
dwarfui.services = {
    TooltipServiceProvider=TooltipServiceProvider,
    ContextMenuServiceProvider=ContextMenuServiceProvider,
}
```

The namespace is closed and read-only. Adding a supported DwarfUI service adds
one explicitly named provider type. Consumers cannot register arbitrary
providers or request internal modules through this namespace.

The provider type names are public compatibility contracts. Internal module
paths used to implement them are not.

## Tooltip provider contract

```lua
---@class dwarfui.ServiceProviderOptions
---@field contract_version integer|nil

---@class dwarfui.TooltipServiceProviderClass

---Creates a tooltip service handle backed by the process-wide runtime.
---@param options? dwarfui.ServiceProviderOptions
---@return dwarfui.TooltipServiceProvider
function TooltipServiceProvider:new(options)
end

---@class dwarfui.TooltipServiceProvider
---@field CONTRACT_VERSION integer

---Registers a widget with the shared tooltip service.
---@param widget gui.View
---@return boolean created
function TooltipServiceProvider:register(widget)
end

---Unregisters a widget from the shared tooltip service.
---@param widget gui.View
---@return boolean removed
function TooltipServiceProvider:unregister(widget)
end

---Registers an exact map tile with the shared tooltip service.
---@param options dwarfui.MapTileTooltipRegistrationOptions
---@return dwarfui.MapTileTooltipRegistration
function TooltipServiceProvider:register_map_tile(options)
end

---Updates an exact map-tile tooltip registration atomically.
---@param handle dwarfui.MapTileTooltipRegistration
---@param update dwarfui.MapTileTooltipUpdate
---@return boolean updated
function TooltipServiceProvider:update_map_tile(handle, update)
end

---Removes an exact map-tile tooltip registration.
---@param handle dwarfui.MapTileTooltipRegistration
---@return boolean removed
function TooltipServiceProvider:unregister_map_tile(handle)
end

---Returns copied public diagnostics for the shared tooltip runtime.
---@return table diagnostics
function TooltipServiceProvider:get_diagnostics()
end
```

The handle does not expose the internal tooltip presenter, poller, target
detector, render-hook manager, mutable process state, observer setter, or
shutdown operation.

## Context-menu provider contract

```lua
---@class dwarfui.ContextMenuServiceProviderClass

---Creates a context-menu handle backed by the process-wide runtime.
---@param options? dwarfui.ServiceProviderOptions
---@return dwarfui.ContextMenuServiceProvider
function ContextMenuServiceProvider:new(options)
end

---@class dwarfui.ContextMenuServiceProvider
---@field CONTRACT_VERSION integer

---Registers or replaces a widget context-menu definition.
---@param widget gui.View
---@param definition dwarfui.ContextMenuDefinition
---@return boolean created
function ContextMenuServiceProvider:register(widget, definition)
end

---Updates an existing widget context-menu definition.
---@param widget gui.View
---@param definition dwarfui.ContextMenuDefinition
---@return boolean updated
function ContextMenuServiceProvider:update(widget, definition)
end

---Removes a widget context-menu registration.
---@param widget gui.View
---@return boolean removed
function ContextMenuServiceProvider:unregister(widget)
end

---Registers an exact map-tile context menu.
---@param options table
---@return dwarfui.ContextMenuMapRegistrationHandle
function ContextMenuServiceProvider:register_map_tile(options)
end

---Updates an exact map-tile context-menu registration atomically.
---@param handle dwarfui.ContextMenuMapRegistrationHandle
---@param options table
---@return boolean updated
function ContextMenuServiceProvider:update_map_tile(handle, options)
end

---Removes an exact map-tile context-menu registration.
---@param handle dwarfui.ContextMenuMapRegistrationHandle
---@return boolean removed
function ContextMenuServiceProvider:unregister_map_tile(handle)
end

---Returns copied public diagnostics for the shared context-menu runtime.
---@return table diagnostics
function ContextMenuServiceProvider:get_diagnostics()
end
```

The handle does not expose the internal presentation factory, input-hook
manager, screen, renderer, registration manager, mutable process state, or
shutdown operation.

## Handle and singleton semantics

Provider handles and runtime services have intentionally different lifetimes:

- every `new()` call may return a distinct lightweight handle;
- handles contain no authoritative registration or presentation state;
- all tooltip handles delegate to one process-wide tooltip facade and runtime;
- all context-menu handles delegate to one process-wide context-menu facade and
  runtime;
- dropping a handle does not shut down its runtime service or remove
  registrations;
- ordinary repeated construction never replaces a singleton, registration
  manager, presenter, hook manager, or active service generation; and
- one consumer cannot mutate another consumer's handle.

Provider methods use colon-call semantics. The handle stores only a private
reference to its validated facade. Each method delegates directly and does not
copy, recreate, or own the underlying service.

This is preferable to returning one mutable shared facade table: a consumer may
attach fields to its own handle without changing the object held by every other
plugin. Provider classes and method implementations remain read-only exports.

## Internal acquisition system

The two public provider classes share a private acquisition helper. The helper
owns typed internal provider specifications containing:

- required shared-infrastructure initializers;
- the private public-facade loader;
- expected contract version;
- required public operations; and
- the process-state slot containing the validated facade.

The helper is not exported through `dwarfui.services`. It can use an internal
immutable numeric discriminator, but external users never see or pass one.

Constructing a tooltip handle conceptually performs:

```text
TooltipServiceProvider:new()
        |
        +-- validate private provider process state
        +-- install shared widget contracts idempotently
        +-- load tooltip facade and private prerequisites
        +-- validate tooltip contract
        +-- retain the validated process-wide facade
        `-- return a new lightweight tooltip handle
```

Context-menu construction uses the parallel provider specification. Acquiring
one service does not eagerly construct or validate unrelated DwarfUI features.

## Initialization and partial-state behavior

Private provider state lives under a DwarfUI-owned key in `dfhack.dwarfui`,
alongside existing process-wide service state. Correctness must not depend only
on DFHack caching the root script environment.

Acquisition is transactional:

- mark the selected service acquisition as in progress;
- cache no facade until every prerequisite and contract check succeeds;
- clear the in-progress marker after failure;
- reject reentrant acquisition as cyclic or partial initialization;
- reuse already validated shared infrastructure and service facades;
- validate cached contract shape before creating another handle; and
- never repair normal acquisition by clearing a script environment.

If initialization fails halfway through, no handle is returned and no partial
facade is published. A later call can succeed after the installation is
corrected or an explicit development reload completes.

## Failure contract

Every construction failure uses a consistent prefix and names the provider:

```text
DwarfUI TooltipServiceProvider: <reason>
DwarfUI ContextMenuServiceProvider: <reason>
```

Construction rejects:

- a missing provider implementation, facade, or required infrastructure file;
- malformed private provider process state;
- a facade with a missing or invalid contract version;
- an explicitly requested unsupported contract version;
- a facade missing a required public method;
- a prerequisite load error; and
- reentrant or cyclic initialization.

Missing files and incompatible contracts recommend reinstalling DwarfUI. A
known stale development generation may recommend the explicit `dwarfui reload`
command. Provider construction itself never invokes reload, teardown,
`devel/clear-script-env`, or overlay rescan.

If `reqscript('dwarfui')` cannot resolve, DFHack's missing-script error is the
appropriate indication that DwarfUI itself is absent.

## Contract versioning

Each provider-backed service handle exposes its service's integer major
`CONTRACT_VERSION`. The initial tooltip and context-menu contracts are version
1.

The zero-argument `new()` form selects the installed contract and is the
recommended simple pattern while DwarfUI remains pre-1.0. A consumer that needs
strict negotiation can request a major version without changing provider
selection:

```lua
local tooltipService =
    dwarfui.services.TooltipServiceProvider:new{
        contract_version=1,
    }
```

Adding a method is compatible. Removing or changing a method, changing
registration semantics, or changing a returned public data shape incompatibly
requires a new service contract major version.

Internal module paths, load order, registry entries, facade module identity,
and runtime implementation classes are not compatibility promises.

## Development reload boundary

`dwarfui reload` remains an explicit developer command. It may retire runtime
owners, clear module environments, rebuild the development registry, and
rescan overlays. None of those operations are reachable from a provider
constructor or handle method.

After a successful explicit reload, the reload path invalidates private facade
caches only after fresh modules are available. New handles then bind to the new
generation. Old handles fail clearly as stale if used after reload; they never
silently mutate into mixed-generation objects.

Reload-specific teardown may intentionally clear context-menu registrations
according to the existing reload lifecycle. Constructing another provider
handle never does so.

The root script's command helpers should become local implementation details so
the module environment presented to consumers contains the typed services
namespace instead of development operations.

## Proposed implementation boundaries

An eventual implementation should be limited to:

- `dwarfui.lua`: export the read-only `services` namespace and keep command
  routing private;
- an internal service-provider helper: own transactional acquisition, process
  facade caches, contract validation, and stale-generation checks;
- a tooltip provider class: construct handles and delegate the existing
  registration facade;
- a context-menu provider class: construct handles and delegate the existing
  registration facade;
- `dwarfui/module_registry.lua`: include new internal modules in development
  reload order;
- package-contract tests: verify the root namespace and both provider types;
  and
- README documentation: replace direct facade imports with the provider
  construction examples.

No consumer plugin migration belongs in the provider implementation task.

## Acceptance tests

| Scenario | Required result |
| --- | --- |
| Cold tooltip construction | Shared infrastructure and tooltip prerequisites initialize privately; a functional typed handle is returned. |
| Cold context-menu construction | Shared infrastructure and context-menu prerequisites initialize privately; a functional typed handle is returned. |
| Repeated construction | Distinct handles delegate to the same runtime singleton without repeated setup. |
| Multiple consumers | Independent plugins retain each other's registrations and share the same backend service. |
| Cross-service construction | Constructing the second provider reuses shared infrastructure without replacing the first service. |
| Runtime preservation | Registrations, active intent/menu state, hooks, and diagnostics survive ordinary repeated construction. |
| Handle isolation | Mutating or discarding one consumer handle cannot mutate or shut down another consumer's service. |
| Partial provider state | Construction fails clearly without reload, environment clearing, or singleton replacement. |
| Contract rejection | Unsupported requested versions and malformed facades fail before a handle is returned. |
| Initialization failure | No facade is published, the in-progress marker is cleared, and a later healthy retry can succeed. |
| Development separation | Constructors and handle methods never invoke reload, teardown, environment clearing, or overlay rescan. |
| Stale handle | A handle from an explicitly retired generation fails clearly instead of calling mixed-generation code. |
| Package contract | Root namespace, provider classes, helper, service facades, documentation, and tests exist in the packaged mod. |

## Rejected alternatives

### Global `dwarfui.get()` with a discriminator

This makes the root function accept a union of unrelated return types and asks
the consumer to select a service with an enum or string. Explicit provider
types give each constructor and returned handle a precise static contract.

### Public internal module paths

Documenting `reqscript('dwarfui/tooltip/api')` or
`reqscript('dwarfui/context_menu/api')` makes package layout a compatibility
promise and gives no common installation or initialization boundary.

### Provider followed by `get()`

Requiring both `Provider:new()` and `provider:get()` introduces a second step
without a meaningful lifetime or selection decision. DwarfUI providers always
bind to their one process-wide service, so construction can directly return the
usable handle.

### Returning internal service objects

Internal services expose lifecycle and mediation operations that consumers must
not call. Provider handles delegate only the narrow registration contracts.

### Eager complete-registry initialization

A tooltip consumer should not fail because an unrelated feature cannot load.
The development module registry and consumer service acquisition serve
different purposes.

### Automatic repair by development reload

Clearing module environments during normal construction can destroy shared
registrations and service ownership. Partial installations fail clearly;
destructive repair remains explicit.

## Recommendation

Adopt typed provider-backed handles with this canonical consumer pattern:

```lua
local dwarfui = reqscript('dwarfui')
local tooltipService =
    dwarfui.services.TooltipServiceProvider:new()
```

Keep provider construction lazy and transactional, keep runtime services
process-wide, give each consumer an isolated lightweight handle, and keep all
development reload behavior outside provider construction and service methods.
