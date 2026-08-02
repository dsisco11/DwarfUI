--@ module=true

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')
local provider_module = reqscript('dwarfui/hotkeys/layout_provider')
local provider_api = provider_module.HotkeyLayoutProvider or provider_module
local model_module = reqscript('dwarfui/hotkeys/model')
local model_api = model_module.HotkeyGroupModel and model_module or
    {HotkeyGroupModel=model_module}
local geometry_module = reqscript('dwarfui/hotkeys/geometry')
local geometry = geometry_module.HotkeyGeometry or geometry_module

---@enum dwarfui.FortressBottomMiddleButtonId
FortressBottomMiddleButtonId = immutable_enum.define({
    DIG=1,
    CHOP=2,
    GATHER=3,
    SMOOTH=4,
    ERASE=5,
    BUILDING=6,
    STOCKPILES=7,
    ZONES=8,
    BURROWS=9,
    HAULING=10,
    TRAFFIC=11,
    ITEMS=12,
}, 'FortressBottomMiddleButtonId')

---@class dwarfui.FortressBottomMiddleGroup
FortressBottomMiddleGroup = {}
FortressBottomMiddleGroup.FortressBottomMiddleButtonId =
    FortressBottomMiddleButtonId

local BUTTONS = {
    {menu_id=FortressBottomMiddleButtonId.DIG, semantic_id='dig',
        action_binding='D_DESIGNATE_DIG', element_id='dig'},
    {menu_id=FortressBottomMiddleButtonId.CHOP, semantic_id='chop',
        action_binding='D_DESIGNATE_CHOP', element_id='chop'},
    {menu_id=FortressBottomMiddleButtonId.GATHER, semantic_id='gather',
        action_binding='D_DESIGNATE_GATHER', element_id='gather'},
    {menu_id=FortressBottomMiddleButtonId.SMOOTH, semantic_id='smooth',
        action_binding='D_DESIGNATE_SMOOTH', element_id='smooth'},
    {menu_id=FortressBottomMiddleButtonId.ERASE, semantic_id='erase',
        action_binding='D_DESIGNATE_ERASE', element_id='erase'},
    {menu_id=FortressBottomMiddleButtonId.BUILDING, semantic_id='building',
        action_binding='D_BUILDING', element_id='building'},
    {menu_id=FortressBottomMiddleButtonId.STOCKPILES,
        semantic_id='stockpiles', action_binding='D_STOCKPILES',
        element_id='stockpiles'},
    {menu_id=FortressBottomMiddleButtonId.ZONES, semantic_id='zones',
        action_binding='D_CIVZONE', element_id='zones'},
    {menu_id=FortressBottomMiddleButtonId.BURROWS, semantic_id='burrows',
        action_binding='D_BURROWS', element_id='burrows'},
    {menu_id=FortressBottomMiddleButtonId.HAULING, semantic_id='hauling',
        action_binding='D_HAULING', element_id='hauling'},
    {menu_id=FortressBottomMiddleButtonId.TRAFFIC, semantic_id='traffic',
        action_binding='D_DESIGNATE_TRAFFIC', element_id='traffic'},
    {menu_id=FortressBottomMiddleButtonId.ITEMS, semantic_id='items',
        action_binding='D_DESIGNATE_ITEMS', element_id='items'},
}

local ELEMENT_OFFSETS = {
    dig={x1=1, x2=4},
    chop={x1=5, x2=8},
    gather={x1=9, x2=12},
    smooth={x1=13, x2=16},
    erase={x1=17, x2=20},
    building={x1=22, x2=25},
    stockpiles={x1=26, x2=29},
    zones={x1=30, x2=33},
    burrows={x1=35, x2=38},
    hauling={x1=39, x2=42},
    traffic={x1=43, x2=46},
    items={x1=48, x2=51},
}

---Returns whether fortress main mode is the active focused viewscreen.
---@return boolean
local function active_provider()
    local viewscreen = dfhack and dfhack.gui and
        dfhack.gui.getDFViewscreen and dfhack.gui.getDFViewscreen(true) or nil
    return viewscreen ~= nil and
        dfhack.gui.matchFocusString('dwarfmode/Default', viewscreen)
end

---Returns the current DF screen dimensions.
---@return integer|nil width
---@return integer|nil height
local function dimensions_provider()
    local gps = df.global and df.global.gps
    return gps and gps.dimx or nil, gps and gps.dimy or nil
end

---Reads one rendered tile without changing input or screen state.
---@param x integer
---@param y integer
---@return table|userdata|nil
local function read_tile(x, y)
    local screen = dfhack and dfhack.screen
    return screen and screen.readTile and screen.readTile(x, y) or nil
end

---Returns the inclusive bottom-band search region for the current screen.
---@param context dwarfui.HotkeySamplingContext
---@return dwarfui.HotkeyRect|nil
local function search_region(context)
    if not context.width or not context.height or context.width < 53 then
        return nil
    end
    return {x1=0, y1=math.max(0, context.height - 8),
        x2=context.width - 1, y2=context.height - 1}
end

---Returns whether a component matches the native segmented middle toolbar.
---@param component dwarfui.HotkeyGeometryComponent
---@param context dwarfui.HotkeySamplingContext
---@return boolean
local function is_middle_toolbar(component, context)
    local width = geometry.width(component)
    local height = geometry.height(component)
    return width == 53 and height == 3 and component.cell_count == 159 and
        component.y2 >= context.height - 2 and
        component.x1 >= math.floor(context.width * 0.25) and
        component.x2 <= math.ceil(context.width * 0.75)
end

---Resolves the uniquely identified segmented middle toolbar.
---@param context dwarfui.HotkeySamplingContext
---@param definition dwarfui.HotkeyGroupDefinition
---@return dwarfui.HotkeyGroupLayout|nil
---@return dwarfui.HotkeyLayoutFailure|nil
local function layout_provider(context, definition)
    local region = search_region(context)
    if not region or type(context.read_tile) ~= 'function' then
        return provider_api.failure(
            provider_api.HotkeyGroupState.UNAVAILABLE,
            'missing_sampling_context')
    end
    local matches = {}
    for _, component in ipairs(geometry.scan_components(
            region, context.read_tile)) do
        if is_middle_toolbar(component, context) then
            matches[#matches + 1] = component
        end
    end
    if #matches == 0 then
        return provider_api.failure(
            provider_api.HotkeyGroupState.UNAVAILABLE, 'not_found')
    end
    if #matches > 1 then
        return provider_api.failure(
            provider_api.HotkeyGroupState.AMBIGUOUS, 'ambiguous')
    end

    local component = matches[1]
    local elements = {}
    local signature_elements = {}
    local element_bounds = {}
    for element_id, offsets in pairs(ELEMENT_OFFSETS) do
        local bounds = {
            x1=component.x1 + offsets.x1,
            y1=component.y1,
            x2=component.x1 + offsets.x2,
            y2=component.y2,
        }
        elements[element_id] = {element_id=element_id, bounds=bounds}
        signature_elements[element_id] = bounds
        element_bounds[#element_bounds + 1] = bounds
    end
    local bounds = geometry.union(element_bounds)
    local signature = bounds and geometry.make_signature(
        definition.group_id, bounds, signature_elements) or nil
    if not signature then
        return provider_api.failure(
            provider_api.HotkeyGroupState.UNAVAILABLE,
            'malformed_extraction')
    end
    return {
        group_id=definition.group_id,
        bounds=bounds,
        elements=elements,
        signature=signature .. ('|%dx%d'):format(
            context.width, context.height),
    }
end

---@type dwarfui.HotkeyGroupDefinition
FortressBottomMiddleGroup.definition = {
    group_id='fortress-bottom-middle-toolbar',
    source_kind=provider_api.HotkeyGeometrySourceKind.CUSTOM,
    active_provider=active_provider,
    layout_provider=layout_provider,
    buttons=BUTTONS,
    placement={anchor=1, inset_x=0, inset_y=0},
}

---Creates the generic model configured for the fortress middle toolbar.
---@return dwarfui.HotkeyGroupModel
function FortressBottomMiddleGroup.create_model()
    return model_api.HotkeyGroupModel{
        definition=FortressBottomMiddleGroup.definition,
        dimensions_provider=dimensions_provider,
        active_provider=active_provider,
        read_tile=read_tile,
    }
end
