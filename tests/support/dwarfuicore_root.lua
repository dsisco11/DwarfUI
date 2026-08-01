---Resolves the separately owned DwarfUICore checkout used by DwarfUI unit tests.
---@return string root
local function resolve_dwarfuicore_root()
    local separator = package.config:sub(1, 1)
    local dwarfui_root = require('support.repo_root')
    local root = dwarfui_root .. separator .. '..' .. separator ..
        'DwarfUICore'
    local probe = io.open(root .. separator .. 'src' .. separator ..
        'scripts_modinstalled' .. separator .. 'dwarfuicore' .. separator ..
        'class.lua', 'rb')
    assert(probe,
        'DwarfUI unit tests require the sibling DwarfUICore checkout at ' .. root)
    probe:close()
    return root
end

return resolve_dwarfuicore_root()
