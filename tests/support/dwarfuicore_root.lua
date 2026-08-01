---Resolves the explicitly selected DwarfUICore source checkout for unit tests.
---@return string root
local function resolve_dwarfuicore_root()
    local root = os.getenv('DWARFUICORE_SOURCE')
    assert(root and root ~= '',
        'DwarfUI unit tests require an explicit DWARFUICORE_SOURCE')
    local separator = package.config:sub(1, 1)
    local probe = io.open(root .. separator .. 'src' .. separator ..
        'scripts_modinstalled' .. separator .. 'dwarfuicore' .. separator ..
        'class.lua', 'rb')
    assert(probe,
        'DWARFUICORE_SOURCE is not a DwarfUICore repository root: ' ..
            root)
    probe:close()
    return root
end

return resolve_dwarfuicore_root()
