--@ module=true

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')
local provider_module = reqscript('dwarfui/hotkeys/layout_provider')
local provider_api = provider_module.HotkeyLayoutProvider or provider_module
local model_module = reqscript('dwarfui/hotkeys/model')
local model_api = model_module.HotkeyGroupModel and model_module or
    {HotkeyGroupModel=model_module}
local geometry_module = reqscript('dwarfui/hotkeys/geometry')
local geometry_api = geometry_module.HotkeyGeometry or geometry_module

---@enum dwarfui.FortressMainButtonId
FortressMainButtonId = immutable_enum.define({
    CITIZENS=1,
    TASKS=2,
    PLACES=3,
    LABOR=4,
    ORDERS=5,
    NOBLES=6,
    OBJECTS=7,
    JUSTICE=8,
}, 'FortressMainButtonId')

---@class dwarfui.FortressMainGroup
FortressMainGroup = {}
FortressMainGroup.FortressMainButtonId = FortressMainButtonId

local BUTTONS = {
    {menu_id=FortressMainButtonId.CITIZENS, semantic_id='citizens', action_binding='D_UNITLIST', element_id='citizens'},
    {menu_id=FortressMainButtonId.TASKS, semantic_id='tasks', action_binding='D_JOBLIST', element_id='tasks'},
    {menu_id=FortressMainButtonId.PLACES, semantic_id='places', action_binding='D_LOCATIONS', element_id='places'},
    {menu_id=FortressMainButtonId.LABOR, semantic_id='labor', action_binding='D_LABOR', element_id='labor'},
    {menu_id=FortressMainButtonId.ORDERS, semantic_id='orders', action_binding='D_ORDERS', element_id='orders'},
    {menu_id=FortressMainButtonId.NOBLES, semantic_id='nobles', action_binding='D_NOBLES', element_id='nobles'},
    {menu_id=FortressMainButtonId.OBJECTS, semantic_id='objects', action_binding='D_ARTLIST', element_id='objects'},
    {menu_id=FortressMainButtonId.JUSTICE, semantic_id='justice', action_binding='D_JUSTICE', element_id='justice'},
}

---Returns whether fortress main mode is the active focused viewscreen.
---@return boolean
local function active_provider()
    local viewscreen = dfhack and dfhack.gui and dfhack.gui.getDFViewscreen and
        dfhack.gui.getDFViewscreen(true) or nil
    return viewscreen ~= nil and dfhack.gui.matchFocusString('dwarfmode/Default', viewscreen)
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
---@return table|nil
local function read_tile(x, y)
    local screen = dfhack and dfhack.screen
    return screen and screen.readTile and screen.readTile(x, y) or nil
end

---Returns the inclusive bottom-band search region for the current screen.
---@param context dwarfui.HotkeySamplingContext
---@return dwarfui.HotkeyRect|nil
local function search_region(context)
    if not context.width or not context.height or context.width < 8 then return nil end
    return {x1=0, y1=math.max(0, context.height - 8),
        x2=context.width - 1, y2=context.height - 1}
end

---Rejects components that are not plausible fortress main toolbar strips.
---@param component dwarfui.HotkeyGeometryComponent
---@param context dwarfui.HotkeySamplingContext
---@return boolean
local function component_predicate(component, context)
    local width = component.x2 - component.x1 + 1
    local height = component.y2 - component.y1 + 1
    return component.cell_count >= 6 and width >= 3 and height >= 2 and
        component.y2 >= context.height - 2 and
        width <= math.floor(context.width * 0.45)
end

---@type dwarfui.HotkeyGroupDefinition
FortressMainGroup.definition = {
    group_id='fortress-main-toolbar',
    source_kind=provider_api.HotkeyGeometrySourceKind.RENDERED_TILES,
    active_provider=active_provider,
    buttons=BUTTONS,
    placement={anchor=1, inset_x=0, inset_y=0},
}

FortressMainGroup.definition.layout_provider = provider_api.rendered_strip({
    search_region=search_region,
    expected_count=#BUTTONS,
    axis=geometry_api.HotkeyStripAxis.HORIZONTAL,
    element_ids={'citizens', 'tasks', 'places', 'labor', 'orders', 'nobles', 'objects', 'justice'},
    component_predicate=function(component)
        local width = component.x2 - component.x1 + 1
        local height = component.y2 - component.y1 + 1
        return component.cell_count >= 6 and width >= 3 and height >= 2 and
            width % #BUTTONS == 0 and width / #BUTTONS >= height
    end,
    signature_data=function(context)
        return {width=context.width, height=context.height, band='bottom-8'}
    end,
})

---Creates the generic model configured for the fortress main toolbar.
---@return dwarfui.HotkeyGroupModel
function FortressMainGroup.create_model()
    return model_api.HotkeyGroupModel{
        definition=FortressMainGroup.definition,
        dimensions_provider=dimensions_provider,
        active_provider=active_provider,
        read_tile=read_tile,
    }
end
