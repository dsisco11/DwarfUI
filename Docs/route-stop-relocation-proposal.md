# Minecart route-stop relocation proposal

## Background

Right-clicking a same-z route stop marker already opens a context menu entry labeled
`Relocate / Change location`, but the action is currently only a placeholder and
does not move the stop.

The route markers and registration lifecycle already exist in
`src/scripts_modinstalled/dwarfui-minecart-route-markers.lua`. The missing piece
is applying a new same-z tile position through a native-feeling prompt and then
updating the active route stop.

## Desired behavior

- Keep the existing map marker and context-menu architecture.
- Replace the placeholder alert with a map-location selection flow.
- When a relocation is confirmed, update the selected route stop to the new map tile and keep the same route selected.
- Maintain safe behavior if map selection is cancelled.
- Preserve existing route context-menu flow for other stops and menu actions.

## Proposed implementation

### 1) Add a UserPrompt entrypoint in DwarfUI service binding

File: `src/scripts_modinstalled/dwarfui/services.lua`

- Extend the DwarfUI service shim so the package has a namespace-bound
`UserPromptService` alongside `TooltipService` and `ContextMenuService`.
- Use the existing immutable service pattern in this module:
  - `CONTRACT_MAJOR = 1`
  - `CONSUMER_NAMESPACE = 'dwarfui'`
- Instantiate:
  - `core_services.UserPromptServiceProvider:new(CONTRACT_MAJOR, CONSUMER_NAMESPACE)`

### 2) Replace placeholder context action with a prompt request

File: `src/scripts_modinstalled/dwarfui-minecart-route-markers.lua`

- In `MinecartRouteMarkersOverlay:create_stop_context_menu_definition`, change the
  `Relocate / Change location` entry action to open a map-location prompt through
  `services.UserPromptService:prompt_map_location(...)`.
- Keep the action and title text constants, but remove direct `dialogs.showMessage`
  usage for relocation.
- Keep context-menu registration and title generation as-is so tests and existing
  menu behavior remain stable.

### 3) Implement relocation completion path

Inside the relocation handler:

- Use captured immutable IDs from the menu definition:
  - target route id
  - target stop id
- In `on_select(position)`:
  - resolve fresh `df.global.plotinfo.hauling` state
  - validate that the owning route and stop still exist and match expected ids
  - return safely with no mutation if validation fails
  - if `position == nil`, treat as no-op cancellation-like outcome
  - write a detached `{x, y, z}` into the native stop position
- In `on_cancel`, return without mutation.
- Keep all callback work idempotent and tolerant of stale native state after world/UI changes.

### 4) Preserve selection and visibility behavior

- Do not alter `resolve_selected_route`, rail behavior, or map-tooltip registration
  ownership.
- Keep existing selection clear paths in `overlay_onupdate` and local teardown.
- Ensure a relocation commit updates existing overlays through existing render cycle
  (same route marker projection + sync logic).

### 5) Handle prompt conflicts

- Keep context-menu behavior unchanged except during active prompt:
  - no-op if `prompt_map_location` throws `SERVICE_BUSY`.
  - route-stop menu action should still fail gracefully and keep overlay state valid.
- If possible, surface a single user-facing message via existing alert path only for
  explicit prompt invocation failure cases not already represented by the local
  no-op path.

## Validation plan

### Unit tests

File: `tests/minecart_route_overlay.spec.lua`

- Add a mock `UserPromptService` in the overlay harness.
- Replace "Not yet implemented" assertion with:
  - `create_stop_context_menu_definition` creates a relocate entry bound to
    `prompt_map_location`.
  - `on_select` is wired with route and stop identity data.
  - the `on_select` path mutates same-z stop position from a callback position.
  - `on_cancel` does not mutate stop data.
- Add a guard test for stale IDs and missing stop lookup during callback.

### Native coverage

File: `tests/minecart_route/route_stop_context_menu.ds.lua`

- Update the final menu acceptance case:
  - selecting `Relocate / Change location` opens the UserPrompt workflow.
  - left-click path updates stop position and returns to hauling.
  - right-click or LEAVESCREEN path leaves stop position unchanged and returns cleanly.

### Regression checks

- `Docs/project.todo` should update:
  - checkbox for route-stop update should become in progress/pending as per project
    tracking.
- Keep existing behavior for `Zoom to this stop` and non-z indicator actions intact.

## Risk and dependency notes

- The proposal depends on approved `dwarfuicore/services` `UserPromptService`
  contract v1 availability in the active build.
- Native stop position assignment depends on current `df.global.plotinfo.hauling`
  schema in the target DF version; this path must guard against missing routes,
  missing stops, and nil positions.
- Keep prompt callback callbacks short and non-throwing where possible; route-stop
  state should remain unchanged on callback failure.

## Exit criteria

- Context menu still shows `Route Stop: <name>`.
- `Relocate / Change location` no longer shows a placeholder alert.
- A left-click-confirmed relocation call updates the active same-z stop position.
- Cancellation paths do not mutate stop state.
- Existing tooltip/context-menu registrations continue to pass unit and native
  lifecycle tests.
