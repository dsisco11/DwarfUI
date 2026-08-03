# Reusable Hotkey Groups

The reusable hotkey subsystem separates native-control discovery from binding
resolution and rendering. A new group supplies feature-specific activity,
geometry, and button semantics. The shared model and overlay own binding
lookup, caching, bounded layout, coordinate conversion, and label rendering.

The public modules are:

- `dwarfui/hotkeys/geometry`: inclusive rectangle validation, connected
  components, repeated strips, and geometry signatures.
- `dwarfui/hotkeys/layout_provider`: validated rendered-strip and
  native-control adapters plus the custom-provider boundary.
- `dwarfui/hotkeys/model`: binding resolution, label normalization, caching,
  and snapshots.
- `dwarfui/hotkeys/overlay`: bounded pass-through rendering.
- `dwarfui/hotkeys/groups/*`: concrete feature-owned definitions.

## Define and register a group

1. Add a production module under `dwarfui/hotkeys/groups/`. Start it with
   `--@ module=true`, load project modules with `reqscript()`, and export a
   named group table through the DFHack module environment.
2. Define a stable `group_id`, an immutable numeric enum for any closed button
   identity set, an activity provider, a layout provider, button definitions,
   and label placement.
3. Build `HotkeyGroupModel` with the definition and the feature's screen,
   activity, and tile collaborators.
4. Register the group module in `dwarfui/module_registry.lua`. Geometry must
   precede layout providers, layout providers must precede models, and models
   must precede concrete groups. A consumer must always follow its
   dependencies.
5. Add a thin overlay class derived from `HotkeyGroupOverlay` and publish it in
   the overlay script's `OVERLAY_WIDGETS` table. If it uses a new overlay
   script, add that script to `OVERLAY_SCRIPTS` in `dwarfui.lua` so reload can
   retire and rediscover it.
6. Add isolated-load, provider, model, overlay-registration, registry-order,
   and package-contract coverage. The package verifier must explicitly require
   the new production files.

Group discovery must be read-only. It must not move the OS pointer, assign
virtual pointer coordinates, synthesize clicks, or open native panels.

## Choose a geometry source

| Source | Use it when | Required adapter behavior |
| --- | --- | --- |
| Native structure | DF exposes a stable non-widget object containing control rectangles. | Locate the object and extract a complete element map. |
| Widget traversal | The located root is proven to be a `df.widget_container`. | Traverse only after the instance check and return screen-space rectangles. |
| Rendered signature | No stable native structure exists, but a unique native tile pattern is visible. | Restrict the search region, validate candidates, and reject zero or multiple matches. |
| Custom provider | Geometry is segmented, signature-based, or otherwise cannot fit the standard adapters. | Return the canonical layout or a typed failure without changing generic modules. |

Do not run widget traversal merely because a value resembles a widget. The
native-control provider calls `walk_widgets` only for a confirmed
`df.widget_container`; other objects go through the feature-specific
`extract` callback.

Rendered discovery should use the smallest stable region and enough native
signature data to distinguish the intended group from nearby controls. A
rendered-strip provider is appropriate only when one connected component can
be partitioned into equal repeated elements. Segmented strips or sprite
catalog signatures belong in a custom provider.

## Coordinate and lifecycle rules

- Provider rectangles use inclusive screen coordinates. Every element must be
  contained by the returned group bounds.
- `HotkeyGroupOverlay` fits its frame to group bounds and converts each element
  to frame-local coordinates in `onRenderBody()`. Concrete overlays must not
  pre-convert coordinates or allocate a fullscreen rendering host.
- A provider signature must change whenever geometry or any interpretation
  input changes. Include current screen dimensions in `signature_data` even
  when the rectangles happen to remain unchanged.
- Providers must return exactly one valid layout. Zero matches are
  `UNAVAILABLE`; multiple matches are `AMBIGUOUS`. Never choose the first
  plausible candidate.
- The model rechecks the provider on every snapshot. It reuses cached geometry
  only while the provider signature is unchanged, but resolves bindings on
  every snapshot so rebinding is immediately visible.
- Inactive, unavailable, ambiguous, malformed, and incomplete groups clear
  stale cached geometry and render no labels for that group.
- A missing optional element or binding suppresses only that button. One
  group's failure must not affect another group's model, frame, or labels.
- Overlay input always passes through to the native interface.

## Minimal second-group example

This schematic group uses the native-control adapter instead of copying the
fortress rendered-toolbar implementation. The feature module represented by
`example/native_controls` owns knowledge of its native structures and returns
screen-space rectangles.

```lua
--@ module=true

local provider_module = reqscript('dwarfui/hotkeys/layout_provider')
local provider = provider_module.HotkeyLayoutProvider or provider_module
local model_module = reqscript('dwarfui/hotkeys/model')
local Model = model_module.HotkeyGroupModel or model_module
local overlay_module = reqscript('dwarfui/hotkeys/overlay')
local controls = reqscript('example/native_controls')

---@class example.StatusHotkeyGroup
StatusHotkeyGroup = {}

---Returns whether the example status panel is active.
---@return boolean
local function is_active()
    return controls.is_active()
end

---Returns the current screen dimensions.
---@return integer|nil width
---@return integer|nil height
local function dimensions()
    local gps = df.global and df.global.gps
    return gps and gps.dimx or nil, gps and gps.dimy or nil
end

---@type dwarfui.HotkeyGroupDefinition
StatusHotkeyGroup.definition = {
    group_id='example-status-actions',
    source_kind=provider.HotkeyGeometrySourceKind.NATIVE_CONTROL,
    active_provider=is_active,
    buttons={
        {semantic_id='inspect', action_binding='D_EXAMPLE_INSPECT',
            element_id='inspect'},
        {semantic_id='toggle', action_binding='D_EXAMPLE_TOGGLE',
            element_id='toggle'},
    },
    placement={anchor=overlay_module.HotkeyLabelAnchor.BOTTOM_RIGHT,
        inset_x=0, inset_y=0},
}

StatusHotkeyGroup.definition.layout_provider = provider.native_control({
    locate=function()
        return controls.find_root()
    end,
    is_widget_container=function(root)
        return df.widget_container:is_instance(root)
    end,
    walk_widgets=function(root)
        return controls.extract_widget_elements(root)
    end,
    extract=function(root)
        return controls.extract_native_elements(root)
    end,
    signature_data=function(_, context)
        return {width=context.width, height=context.height}
    end,
})

---Creates a model for the example status controls.
---@return dwarfui.HotkeyGroupModel
function StatusHotkeyGroup.create_model()
    return Model{
        definition=StatusHotkeyGroup.definition,
        dimensions_provider=dimensions,
        active_provider=is_active,
    }
end
```

The overlay registration remains thin:

```lua
--@ module=true

local hotkey_overlay = reqscript('dwarfui/hotkeys/overlay')
local status_group = reqscript('example/status_hotkeys')

---@class example.StatusHotkeysOverlay: dwarfui.HotkeyGroupOverlay
StatusHotkeysOverlay = defclass(StatusHotkeysOverlay,
    hotkey_overlay.HotkeyGroupOverlay)
StatusHotkeysOverlay.ATTRS{
    viewscreens='example/Status',
    model_builder=function()
        return status_group.StatusHotkeyGroup.create_model()
    end,
    label_anchor_kind=hotkey_overlay.HotkeyLabelAnchor.BOTTOM_RIGHT,
}

OVERLAY_WIDGETS = {status_hotkeys=StatusHotkeysOverlay}
```

Replace the example action names and native-control adapter with the owning
feature's real public interfaces. The generic geometry, model, and overlay
modules should not change when a group is added.
