# DwarfUI service-provider lifecycle

DwarfUI overlay teardown has two independent responsibilities. Feature-local
cleanup clears overlay-owned selection, widgets, caches, and state without
acquiring or using a DwarfUICore API. Service-registration removal is separate:
ordinary overlay disable can unregister promptly, while root teardown clears the
`dwarfui` tooltip and context-menu namespaces after every overlay has released
its local state.

## Overlay cleanup inventory

`dwarfui-minecart-route-markers` is the only current DwarfUI overlay that owns
service registrations. Its local state is the selected route, pooled action
rail, map-tooltip handle table, registration order, and route ID. During normal
disable, focus loss, selected-route loss, and world unload, it clears that
state and promptly unregisters the captured map-tooltip handles. During root
reload teardown it exposes only `dwarfui_clear_local_state`, leaving
registration removal to namespace clearing.

`dwarfui-mood-popover` owns selected-mood and popover-row state but has no
service registration. `dwarfui-ui-hotkeys` and
`dwarfui-unit-card-task-details` likewise have no DwarfUICore registration or
feature-local teardown state. Root teardown continues to invoke their ordinary
disable callbacks as the safe no-service fallback.

This ordering keeps a Core reload from making feature-local cleanup depend on a
stale API object. Core reload clears its own runtime registrations. Namespace
clearing remains authoritative for a DwarfUI-only reload and teardown; it does
not affect registrations acquired by another namespace in the current Core
generation. A failure during explicit service removal is reported after local
cleanup.
