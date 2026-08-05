--@ module=true

local CONTRACT_MAJOR = 1
local CONSUMER_NAMESPACE = 'dwarfui'

---The namespace-bound tooltip API shared by DwarfUI entrypoints.
---@type dwarfuicore.TooltipServiceApi
TooltipService = nil

---The namespace-bound context-menu API shared by DwarfUI entrypoints.
---@type dwarfuicore.ContextMenuServiceApi
ContextMenuService = nil

---The namespace-bound user-prompt API shared by DwarfUI entrypoints.
---@type dwarfuicore.UserPromptServiceApi
UserPromptService = nil

---Reacquires DwarfUI-bound APIs from the current DwarfUICore generation.
function refresh()
    local core_services = reqscript('dwarfuicore/services')
    local tooltip_service = core_services.TooltipServiceProvider:new(
        CONTRACT_MAJOR, CONSUMER_NAMESPACE)
    local context_menu_service = core_services.ContextMenuServiceProvider:new(
        CONTRACT_MAJOR, CONSUMER_NAMESPACE)
    local user_prompt_service = core_services.UserPromptServiceProvider:new(
        CONTRACT_MAJOR, CONSUMER_NAMESPACE)
    TooltipService = tooltip_service
    ContextMenuService = context_menu_service
    UserPromptService = user_prompt_service
end

---Explicitly clears DwarfUI-owned service namespaces.
---@return boolean changed
function clear_namespaces()
    local tooltip_ok, tooltip_changed = pcall(function()
        return TooltipService:clear_namespace()
    end)
    local context_ok, context_menu_changed = pcall(function()
        return ContextMenuService:clear_namespace()
    end)
    local user_prompt_ok, user_prompt_changed = pcall(function()
        return UserPromptService:clear_namespace()
    end)
    if not tooltip_ok then error(tooltip_changed, 0) end
    if not context_ok then error(context_menu_changed, 0) end
    if not user_prompt_ok then error(user_prompt_changed, 0) end
    return tooltip_changed or context_menu_changed or user_prompt_changed
end

refresh()
