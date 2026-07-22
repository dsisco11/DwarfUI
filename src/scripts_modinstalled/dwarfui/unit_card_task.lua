--@ module=true

---Utilities for rendering destination details for native unit-card haul jobs.

---Returns whether a job currently carries an item as a hauling task.
---@param job df.job|nil
---@return boolean
function is_haul_job(job)
    if not job then return false end
    for _, item_ref in ipairs(job.items) do
        if item_ref.role == df.job_role_type.Hauled then return true end
    end
    return false
end

---Finds the building containing a hauling destination, including stockpiles.
---@param pos df.coord
---@return df.building|nil
local function find_destination_building(pos)
    local building = dfhack.buildings.findAtTile(pos)
    if building then return building end
    for _, stockpile in ipairs(df.global.world.buildings.other.STOCKPILE) do
        if stockpile.z == pos.z and
                dfhack.buildings.containsTile(stockpile, pos.x, pos.y) then
            return stockpile
        end
    end
end

---Builds the text shown beneath a native unit-card hauling row.
---@param unit df.unit|nil
---@return string|nil
function get_haul_destination_text(unit)
    local job = unit and unit.job and unit.job.current_job or nil
    if not is_haul_job(job) then return end
    local pos = job.pos
    if not pos or pos.x < 0 or pos.y < 0 or pos.z < 0 then return end

    local building = find_destination_building(pos)
    local name = building and dfhack.buildings.getName(building) or nil
    if name and name ~= '' then return 'Destination: ' .. name end
    return ('Destination: (%d, %d, %d)'):format(pos.x, pos.y, pos.z)
end
