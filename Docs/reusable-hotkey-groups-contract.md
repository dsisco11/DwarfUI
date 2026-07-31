# Reusable Hotkey Groups Contract

This document defines the public contracts and ownership boundaries for the
reusable hotkey-group subsystem planned in
`Docs/reusable-hotkey-groups.todo`. It records design decisions only; the
generic production modules are introduced by later checklist work.

## Existing-system audit

The current implementation combines reusable behavior and one concrete native
toolbar definition across two files.

`dwarfui/ui_hotkeys.lua` currently owns:

- the fortress main-toolbar semantic enum and eight-button catalog;
- bottom-screen rendered-tile sampling and connected-component discovery;
- equal-width element extraction for the selected native component;
- rectangle validation, group union, and geometry signatures;
- fortress-mode activity and screen-dimension providers;
- DF interface-key lookup and compact label normalization;
- geometry caching, per-button suppression, and snapshot construction.

`dwarfui-ui-hotkeys.lua` currently owns:

- the `dwarfmode/Default` overlay registration;
- construction of the concrete `UiHotkeyModel`;
- frame synchronization with resolved group bounds;
- label anchoring and painting;
- continuous refresh and input pass-through.

The reusable subsystem will own contracts, validation, caching, binding
resolution, coordinate conversion, and rendering. Concrete group definitions
will own screen eligibility, native-source selection, search regions,
candidate validation, semantic elements, and DF actions.

## Public discriminators

All production definitions use immutable numeric enums created through
`dwarfui/utils/immutable_enum`.

```lua
---@enum dwarfui.HotkeyGeometrySourceKind
HotkeyGeometrySourceKind = {
    NATIVE_CONTROL=1,
    RENDERED_TILES=2,
    CUSTOM=3,
}

---@enum dwarfui.HotkeyLabelAnchor
HotkeyLabelAnchor = {
    TOP_LEFT=1,
    TOP_RIGHT=2,
    BOTTOM_LEFT=3,
    BOTTOM_RIGHT=4,
}

---@enum dwarfui.HotkeyGroupState
HotkeyGroupState = {
    INACTIVE=1,
    READY=2,
    UNAVAILABLE=3,
    AMBIGUOUS=4,
}
```

`CUSTOM` identifies a caller-supplied provider whose native source is not one
of the standard adapters. It does not permit an untyped string discriminator.

## Canonical data contracts

```lua
---@class dwarfui.HotkeyRect
---@field x1 integer
---@field y1 integer
---@field x2 integer
---@field y2 integer

---@class dwarfui.HotkeySamplingContext
---@field width integer|nil
---@field height integer|nil
---@field viewscreen df.viewscreen|nil
---@field read_tile fun(x: integer, y: integer): table|nil

---@class dwarfui.HotkeyGroupElement
---@field element_id string
---@field bounds dwarfui.HotkeyRect

---@class dwarfui.HotkeyGroupLayout
---@field group_id string
---@field bounds dwarfui.HotkeyRect
---@field elements table<string, dwarfui.HotkeyGroupElement>
---@field signature string

---@class dwarfui.HotkeyButtonDefinition
---@field semantic_id string
---@field action_binding string
---@field element_id string

---@class dwarfui.HotkeyLabelPlacement
---@field anchor dwarfui.HotkeyLabelAnchor
---@field inset_x integer
---@field inset_y integer

---@class dwarfui.HotkeyLayoutFailure
---@field state dwarfui.HotkeyGroupState
---@field reason string|nil

---@alias dwarfui.HotkeyLayoutProvider fun(context: dwarfui.HotkeySamplingContext, definition: dwarfui.HotkeyGroupDefinition): dwarfui.HotkeyGroupLayout|nil, dwarfui.HotkeyLayoutFailure|nil

---@class dwarfui.HotkeyGroupDefinition
---@field group_id string
---@field source_kind dwarfui.HotkeyGeometrySourceKind
---@field active_provider fun(): boolean
---@field layout_provider dwarfui.HotkeyLayoutProvider
---@field buttons dwarfui.HotkeyButtonDefinition[]
---@field placement dwarfui.HotkeyLabelPlacement

---@class dwarfui.ResolvedHotkeyButton
---@field semantic_id string
---@field action_binding string
---@field element_id string
---@field bounds dwarfui.HotkeyRect
---@field label string

---@class dwarfui.HotkeyGroupSnapshot
---@field group_id string
---@field state dwarfui.HotkeyGroupState
---@field active boolean
---@field layout_signature string
---@field bounds dwarfui.HotkeyRect|nil
---@field buttons dwarfui.ResolvedHotkeyButton[]
```

The ordered `buttons` list controls deterministic rendering order. Geometry is
joined by `element_id`; generic code must not infer semantics from coordinates.
The layout provider owns the source-specific portion of `signature`. Generic
code validates the returned rectangles and incorporates screen dimensions
before comparing cache keys.

## Provider contract

A layout provider may inspect the supplied viewscreen, exposed native
structures, native widget containers, or rendered screen tiles. It returns one
complete semantic layout or a typed failure.

Providers must:

- be read-only;
- return screen-space inclusive rectangles;
- return a stable, nonempty `group_id` matching the definition;
- return a unique element for every semantic element they claim to expose;
- include every source property that can move or resize elements in the layout
  signature;
- reject ambiguous candidates instead of selecting by incidental enumeration
  order;
- traverse children only when the native value is a `df.widget_container`;
- tolerate controls represented by native structures or rendered signatures
  instead of widgets.

Providers must not move the OS pointer, assign virtual pointer coordinates,
send pointer events, synthesize clicks, open native panels, or otherwise mutate
game input or UI state. `gui.simulateInput` may be used by separately scoped
live setup code when a test explicitly needs keyboard navigation, but it is not
a geometry-discovery mechanism.

## Failure and caching contract

- `INACTIVE`: clear cached geometry and return no buttons.
- `UNAVAILABLE`: return no group bounds or buttons; do not retain stale
  geometry from an earlier visible state.
- `AMBIGUOUS`: return no group bounds or buttons; never guess among candidates.
- Incomplete layout: treat the group as unavailable unless the provider
  explicitly defines the missing element as optional.
- Missing element or binding for one optional button: suppress only that
  button.
- Provider exception or malformed result: contain the failure at that group
  boundary and report `UNAVAILABLE`.
- Independent group models never share mutable geometry, cache state, or
  failure state.
- Binding labels are resolved on every snapshot build so binding changes do not
  depend on geometry invalidation.
- Geometry is reused only while dimensions and the provider-owned layout
  signature remain unchanged.

## Compatibility contract

The migration is additive. These current interfaces remain available until a
separate breaking API decision explicitly retires them:

### `dwarfui/ui_hotkeys`

- `UiHotkeyMenuId`, including its existing numeric members;
- `normalize_hotkey_label(raw)`;
- `UiHotkeyModel{...}` and its injectable constructor attributes;
- `UiHotkeyModel:clear_cache()`;
- `UiHotkeyModel:get_layout_signature(...)`;
- `UiHotkeyModel:make_sampling_context(...)`;
- `UiHotkeyModel:refresh_bounds(...)`;
- `UiHotkeyModel:build_snapshot()`;
- snapshot fields `active`, `layout_signature`, `buttons`, and `bounds`;
- resolved-button fields `menu_id`, `semantic_id`, `action_binding`, `bounds`,
  and `label`.

`UiHotkeyModel` will become a wrapper or specialization backed by the generic
model. Existing constructor injection points remain accepted even if adapters
translate them to the new contracts internally.

### `dwarfui-ui-hotkeys`

- class export `UiMenuHotkeysOverlay`;
- overlay registration key `dwarfui-ui-hotkeys.ui_hotkeys`;
- default-enabled behavior;
- `dwarfmode/Default` eligibility;
- passive input behavior;
- the current frame and label configuration attributes where compatible.

The registration key must not change because DFHack persists overlay state by
that key. The class may subclass the generic bounded overlay, and its methods
may delegate to generic implementations, without changing observable behavior.

## Ownership boundaries

| Concern | Generic subsystem | Concrete group definition |
| --- | --- | --- |
| Rectangle validation and translation | Owns | Uses |
| Provider result validation | Owns | Supplies source data |
| Geometry and binding cache policy | Owns | Supplies signature inputs |
| DF binding display and normalization | Owns | Selects action bindings |
| Snapshot construction | Owns | Supplies semantic catalog |
| Label anchoring and bounded rendering | Owns | Selects placement values |
| Viewscreen eligibility | Invokes | Defines |
| Native structure or tile source | Adapts | Selects |
| Search region and candidate validation | Executes callbacks | Defines |
| Element-to-semantic mapping | Joins by ID | Defines |
| Overlay registration and persisted key | Supports | Owns |

Adding another group must require only a group definition, an appropriate
layout provider configuration or adapter, and a thin overlay registration. It
must not require modifying the generic geometry, model, or renderer.
