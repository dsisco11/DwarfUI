--@ module=true

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')
local provider_module = reqscript('dwarfui/hotkeys/layout_provider')
local provider_api = provider_module.HotkeyLayoutProvider or provider_module
local model_module = reqscript('dwarfui/hotkeys/model')
local model_api = model_module.HotkeyGroupModel and model_module or
    {HotkeyGroupModel=model_module}
local geometry_module = reqscript('dwarfui/hotkeys/geometry')
local geometry = geometry_module.HotkeyGeometry or geometry_module

---@enum dwarfui.FortressBottomRightButtonId
FortressBottomRightButtonId = immutable_enum.define({
    SQUADS=1,
    WORLD=2,
}, 'FortressBottomRightButtonId')

---@class dwarfui.FortressBottomRightGroup
FortressBottomRightGroup = {}
FortressBottomRightGroup.FortressBottomRightButtonId =
    FortressBottomRightButtonId

local BUTTONS = {
    {menu_id=FortressBottomRightButtonId.SQUADS, semantic_id='squads',
        action_binding='D_SQUADS', element_id='squads'},
    {menu_id=FortressBottomRightButtonId.WORLD, semantic_id='world',
        action_binding='D_WORLD', element_id='world'},
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

---Returns one native interface sprite tile identifier.
---@param x integer
---@param y integer
---@return integer|nil
local function find_interface_tile(x, y)
    local screen = dfhack and dfhack.screen
    if not screen or type(screen.findGraphicsTile) ~= 'function' then
        return nil
    end
    local ok, tile = pcall(screen.findGraphicsTile, 'INTERFACE_BITS', x, y)
    return ok and type(tile) == 'number' and tile or nil
end

---Returns the numeric graphics tile stored in an indexable screen pen.
---@param pen table|userdata|nil
---@return integer|nil
local function get_tile(pen)
    local pen_type = type(pen)
    if pen_type ~= 'table' and pen_type ~= 'userdata' then return nil end
    local ok, tile = pcall(function() return pen.tile end)
    return ok and type(tile) == 'number' and tile or nil
end

---Builds the stable two-row native sprite signature used for discovery.
---@return integer[]|nil
local function expected_signature()
    local signature = {}
    for y=16,17 do
        for x=24,31 do
            local tile = find_interface_tile(x, y)
            if not tile then return nil end
            signature[#signature + 1] = tile
        end
    end
    return signature
end

---Returns whether the native Squads/World signature begins at a coordinate.
---@param context dwarfui.HotkeySamplingContext
---@param x integer
---@param y integer
---@param signature integer[]
---@return boolean
local function matches_signature(context, x, y, signature)
    local index = 1
    for offset_y=0,1 do
        for offset_x=0,7 do
            if get_tile(context.read_tile(x + offset_x, y + offset_y)) ~=
                    signature[index] then
                return false
            end
            index = index + 1
        end
    end
    return true
end

---Resolves the uniquely identified native Squads/World button group.
---@param context dwarfui.HotkeySamplingContext
---@param definition dwarfui.HotkeyGroupDefinition
---@return dwarfui.HotkeyGroupLayout|nil
---@return dwarfui.HotkeyLayoutFailure|nil
local function layout_provider(context, definition)
    if type(context) ~= 'table' or type(context.width) ~= 'number' or
            type(context.height) ~= 'number' or
            type(context.read_tile) ~= 'function' or context.width < 8 or
            context.height < 3 then
        return provider_api.failure(
            provider_api.HotkeyGroupState.UNAVAILABLE,
            'missing_sampling_context')
    end
    local signature = expected_signature()
    if not signature then
        return provider_api.failure(
            provider_api.HotkeyGroupState.UNAVAILABLE,
            'missing_tile_catalog')
    end
    local matches = {}
    for y=math.max(0, context.height - 8),context.height - 3 do
        for x=math.floor(context.width * 0.75),context.width - 8 do
            if matches_signature(context, x, y, signature) then
                matches[#matches + 1] = {x=x, y=y}
            end
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

    local origin = matches[1]
    local bounds = {x1=origin.x, y1=origin.y,
        x2=origin.x + 7, y2=origin.y + 2}
    local element_bounds = {
        squads={x1=origin.x, y1=origin.y,
            x2=origin.x + 3, y2=origin.y + 2},
        world={x1=origin.x + 4, y1=origin.y,
            x2=origin.x + 7, y2=origin.y + 2},
    }
    local elements = {
        squads={element_id='squads', bounds=element_bounds.squads},
        world={element_id='world', bounds=element_bounds.world},
    }
    local layout_signature = geometry.make_signature(
        definition.group_id, bounds, element_bounds)
    if not layout_signature then
        return provider_api.failure(
            provider_api.HotkeyGroupState.UNAVAILABLE,
            'malformed_extraction')
    end
    return {
        group_id=definition.group_id,
        bounds=bounds,
        elements=elements,
        signature=layout_signature .. ('|%dx%d'):format(
            context.width, context.height),
    }
end

---@type dwarfui.HotkeyGroupDefinition
FortressBottomRightGroup.definition = {
    group_id='fortress-bottom-right-toolbar',
    source_kind=provider_api.HotkeyGeometrySourceKind.CUSTOM,
    active_provider=active_provider,
    layout_provider=layout_provider,
    buttons=BUTTONS,
    placement={anchor=1, inset_x=0, inset_y=0},
}

---Creates the generic model configured for the fortress right toolbar.
---@return dwarfui.HotkeyGroupModel
function FortressBottomRightGroup.create_model()
    return model_api.HotkeyGroupModel{
        definition=FortressBottomRightGroup.definition,
        dimensions_provider=dimensions_provider,
        active_provider=active_provider,
        read_tile=read_tile,
    }
end
