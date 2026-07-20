-- DwarfUI-wide live-test settings and product commands.

---Returns the singleton tooltip service's current read-only diagnostics.
---@return table
local function tooltip_diagnostics()
    local registration = reqscript('dwarfui/tooltip_registration')
    return registration.get_diagnostics()
end

return {
    settings={
        wait={frame_budget=300, timeout_ms=10000},
    },
    commands={
        tooltip_state=tooltip_diagnostics,
    },
}
