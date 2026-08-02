local repo_root = require('support.repo_root')

local separator = package.config:sub(1, 1)

---Returns the absolute path for a repository-relative file.
---@param relative_path string
---@return string path
local function repository_path(relative_path)
    return repo_root .. separator .. relative_path:gsub('/', separator)
end

---Reads one repository-relative text file.
---@param relative_path string
---@return string text
local function read_file(relative_path)
    local file = assert(io.open(repository_path(relative_path), 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

---Returns whether one repository-relative file exists.
---@param relative_path string
---@return boolean exists
local function file_exists(relative_path)
    local file = io.open(repository_path(relative_path), 'rb')
    if not file then return false end
    file:close()
    return true
end

describe('DwarfUI package contract', function()
    it('declares DwarfUICore as an explicit package dependency', function()
        local rockspec = read_file('dwarfui.rockspec')

        assert.is_truthy(rockspec:find('"dwarfuicore >= 0.2.0"', 1, true))
        local _, occurrences = rockspec:gsub('"dwarfuicore >= 0.2.0"', '')
        assert.equals(2, occurrences)
    end)

    it('ships only DwarfUI-owned feature modules', function()
        local expected = {
            'src/scripts_modinstalled/dwarfui.lua',
            'src/scripts_modinstalled/dwarfui/module_registry.lua',
            'src/scripts_modinstalled/dwarfui/services.lua',
            'src/scripts_modinstalled/dwarfui/widgets/asset_button.lua',
            'src/scripts_modinstalled/dwarfui/widgets/hover_action_rail.lua',
            'src/scripts_modinstalled/dwarfui/popover.lua',
            'src/scripts_modinstalled/dwarfui/ui_hotkeys.lua',
            'src/scripts_modinstalled/dwarfui/hotkeys/geometry.lua',
            'src/scripts_modinstalled/dwarfui/hotkeys/layout_provider.lua',
            'src/scripts_modinstalled/dwarfui/hotkeys/model.lua',
            'src/scripts_modinstalled/dwarfui/hotkeys/groups/fortress_main.lua',
            'src/scripts_modinstalled/dwarfui/hotkeys/overlay.lua',
            'src/scripts_modinstalled/dwarfui/mood_popover.lua',
            'src/scripts_modinstalled/dwarfui/minecart_route.lua',
            'src/scripts_modinstalled/dwarfui/unit_card_task.lua',
            'src/scripts_modinstalled/dwarfui-minecart-route-markers.lua',
        }
        for _, path in ipairs(expected) do assert.is_true(file_exists(path)) end

        for _, removed in ipairs({
                'src/scripts_modinstalled/dwarfuicore.lua',
                'src/scripts_modinstalled/dwarfuicore/tooltip/api.lua',
                'src/scripts_modinstalled/dwarfui/tooltip/api.lua',
                'src/scripts_modinstalled/dwarfui/context_menu/api.lua',
                'src/scripts_modinstalled/dwarfui/pointer.lua',
                'src/scripts_modinstalled/dwarfui/widget_extensions.lua'}) do
            assert.is_false(file_exists(removed))
        end
    end)

    it('uses Core APIs from DwarfUI feature integrations', function()
        local minecart_overlay = read_file(
            'src/scripts_modinstalled/dwarfui-minecart-route-markers.lua')
        local minecart_model = read_file(
            'src/scripts_modinstalled/dwarfui/minecart_route.lua')
        local asset_button = read_file(
            'src/scripts_modinstalled/dwarfui/widgets/asset_button.lua')

        assert.is_truthy(minecart_overlay:find(
            "reqscript('dwarfui/services').TooltipService", 1, true))
        assert.is_truthy(minecart_overlay:find(
            "reqscript('dwarfuicore/pointer')", 1, true))
        assert.is_truthy(minecart_model:find(
            "reqscript('dwarfuicore/map_projection')", 1, true))
        assert.is_truthy(asset_button:find(
            "reqscript('dwarfuicore/widget_extensions')", 1, true))
    end)

    it('keeps DwarfUI reload isolated from DwarfUICore reload', function()
        local root = read_file('src/scripts_modinstalled/dwarfui.lua')

        assert.is_nil(root:find("dwarfuicore reload", 1, true))
        assert.is_nil(root:find("dwarfuicore/tooltip", 1, true))
        assert.is_nil(root:find("dwarfuicore/context_menu", 1, true))
        assert.is_truthy(root:find('services.refresh()', 1, true))
        assert.is_truthy(root:find('services.clear_namespaces()', 1, true))
    end)

    it('exposes only the Core public API definitions to LuaLS', function()
        local settings = read_file('.luarc.json')

        assert.is_truthy(settings:find(
            '../DwarfUICore/src/scripts_modinstalled/dwarfuicore/services.lua',
            1, true))
        assert.is_truthy(settings:find(
            '../DwarfUICore/src/scripts_modinstalled/dwarfuicore/service_provider/api.lua',
            1, true))
        assert.is_nil(settings:find(
            '../DwarfUICore/src/scripts_modinstalled/dwarfuicore/tooltip/service.lua',
            1, true))
    end)
end)
