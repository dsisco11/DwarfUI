--@ module=true

local CONTRACT_MAJOR = 1
local CONSUMER_NAMESPACE = 'dwarfui'

---The namespace-bound tooltip API shared by DwarfUI entrypoints.
---@type dwarfuicore.TooltipServiceApi
TooltipService = nil

---The namespace-bound context-menu API shared by DwarfUI entrypoints.
---@type dwarfuicore.ContextMenuServiceApi
ContextMenuService = nil

---Reacquires both DwarfUI APIs from the current DwarfUICore generation.
function refresh()
    local core_services = reqscript('dwarfuicore/services')
    local tooltip_service = core_services.TooltipServiceProvider:new(
        CONTRACT_MAJOR, CONSUMER_NAMESPACE)
    local context_menu_service = core_services.ContextMenuServiceProvider:new(
        CONTRACT_MAJOR, CONSUMER_NAMESPACE)
    TooltipService = tooltip_service
    ContextMenuService = context_menu_service
end

---Explicitly clears both DwarfUI-owned service namespaces.
---@return boolean changed
function clear_namespaces()
    local tooltip_changed = TooltipService:clear_namespace()
    local context_menu_changed = ContextMenuService:clear_namespace()
    return tooltip_changed or context_menu_changed
end

refresh()
