--@ module=true

---Utilities for rendering destination details for native unit-card haul jobs.

---Job types that move an item to a storage or delivery destination.
local HAUL_JOB_TYPES = {
    [df.job_type.BringItemToDepot]=true,
    [df.job_type.BringItemToShop]=true,
    [df.job_type.StoreItemInStockpile]=true,
    [df.job_type.StoreItemInBag]=true,
    [df.job_type.StoreItemInLocation]=true,
    [df.job_type.StoreItemInBarrel]=true,
    [df.job_type.StoreItemInBin]=true,
    [df.job_type.StoreItemInVehicle]=true,
    [df.job_type.DumpItem]=true,
}

---Returns whether a job currently carries an item as a hauling task.
---@param job df.job|nil
---@return boolean
function is_haul_job(job)
    if not job then return false end
    for _, item_ref in ipairs(job.items) do
        if item_ref.role == df.job_role_type.Hauled then return true end
    end
    return HAUL_JOB_TYPES[job.job_type] == true
end

---Returns whether an assigned hauling item has not yet entered an inventory.
---@param item df.item|nil
---@return boolean
local function is_uncollected_item(item)
    return item ~= nil and (item.flags == nil or not item.flags.in_inventory)
end

---Returns the item a hauler has been assigned to collect.
---@param job df.job|nil
---@return df.item|nil
function get_grab_item(job)
    if not is_haul_job(job) then return end
    for _, item_ref in ipairs(job.items) do
        if item_ref.role == df.job_role_type.Hauled and
                is_uncollected_item(item_ref.item) then
            return item_ref.item
        end
    end
    -- Container-loading jobs can expose their pending contents without a
    -- Hauled entry. Preserve that native representation as a fallback.
    for _, item_ref in ipairs(job.items) do
        if item_ref.role == df.job_role_type.QueuedContainer and
                is_uncollected_item(item_ref.item) then
            return item_ref.item
        end
    end
end

---Builds the text shown while a hauler is travelling to collect an item.
---@param unit df.unit|nil
---@return string|nil
function get_grab_item_text(unit)
    local job = unit and unit.job and unit.job.current_job or nil
    local item = get_grab_item(job)
    if not item then return end
    return 'Grab: ' .. dfhack.items.getDescription(item, 0, true)
end

---Truncates a task-detail row to fit within the native unit-card subpanel.
---@param text string|nil
---@param width integer
---@return string|nil
function truncate_panel_text(text, width)
    if not text or #text <= width then return text end
    if width <= 3 then return text:sub(1, width) end
    return text:sub(1, width)
end

---Returns whether a task-detail row exceeds its available panel width.
---@param text string|nil
---@param width integer
---@return boolean
function is_panel_text_truncated(text, width)
    return text ~= nil and #text > width
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
