--@ module=true

-- Pure model support for the fortress mood-icon popover.

---@class dwarfui.MoodPopoverModel: dfhack.class
MoodPopoverModel = defclass(MoodPopoverModel)

local MOOD_LEVELS = {
    {hover_key='INFO_STRESSED_0', hover_index=0, stress_category=6, label='Ecstatic', pen=COLOR_LIGHTGREEN},
    {hover_key='INFO_STRESSED_1', hover_index=1, stress_category=5, label='Happy', pen=COLOR_GREEN},
    {hover_key='INFO_STRESSED_2', hover_index=2, stress_category=4, label='Pleased', pen=COLOR_LIGHTCYAN},
    {hover_key='INFO_STRESSED_3', hover_index=3, stress_category=3, label='Content', pen=COLOR_WHITE},
    {hover_key='INFO_STRESSED_4', hover_index=4, stress_category=2, label='Displeased', pen=COLOR_YELLOW},
    {hover_key='INFO_STRESSED_5', hover_index=5, stress_category=1, label='Unhappy', pen=COLOR_LIGHTRED},
    {hover_key='INFO_STRESSED_6', hover_index=6, stress_category=0, label='Miserable', pen=COLOR_RED},
}

---Gets the native hover-instruction enum table.
---@return table
local function default_hover_instructions()
    return df.main_hover_instruction
end

---Gets the normal DFHack collaborators used to build a mood snapshot.
---@return table
local function default_dependencies()
    return {
        get_active_units=function()
            return df.global.world.units.active
        end,
        is_valid=function(unit)
            return df.isvalid(unit) ~= nil
        end,
        is_citizen=function(unit)
            return dfhack.units.isCitizen(unit, true)
        end,
        get_stress_category=function(unit)
            return dfhack.units.getStressCategory(unit)
        end,
        get_readable_name=function(unit)
            return dfhack.units.getReadableName(unit)
        end,
    }
end

---Returns the seven supported native mood descriptors.
---
---Each descriptor contains the native enum value, DFHack stress category,
---display label, and display pen. The enum names are table-driven rather than
---parsed at runtime so unsupported future enum values cannot be misclassified.
---@param hover_instructions? table
---@return table[]
function MoodPopoverModel:get_descriptors(hover_instructions)
    hover_instructions = hover_instructions or default_hover_instructions()
    local descriptors = {}

    for _, level in ipairs(MOOD_LEVELS) do
        local hover_value = hover_instructions[level.hover_key]
        assert(hover_value ~= nil,
            ('missing native mood hover instruction %s'):format(level.hover_key))
        table.insert(descriptors, {
            hover_value=hover_value,
            hover_index=level.hover_index,
            stress_category=level.stress_category,
            label=level.label,
            pen=level.pen,
        })
    end

    return descriptors
end

---Resolves one native hover value to its supported mood descriptor.
---@param hover_value any
---@param hover_instructions? table
---@return table|nil
function MoodPopoverModel:resolve_hover(hover_value, hover_instructions)
    for _, descriptor in ipairs(self:get_descriptors(hover_instructions)) do
        if hover_value == descriptor.hover_value then
            return descriptor
        end
    end
    return nil
end

---Tests whether an active unit belongs in the native mood-counter population.
---
---Callers supply units from `world.units.active`; this predicate applies the
---remaining established citizen rule.
---@param unit any
---@param is_valid fun(unit: any): boolean|any
---@param is_citizen fun(unit: any): boolean
---@return boolean
function MoodPopoverModel:is_mood_unit(unit, is_valid, is_citizen)
    return unit ~= nil and is_valid(unit) and is_citizen(unit)
end

---Normalizes a readable name for deterministic case-insensitive ordering.
---@param name any
---@return string
function MoodPopoverModel:normalize_name(name)
    return tostring(name or ''):lower()
end

---Builds the ordered unit rows for one mood descriptor from active units.
---
---The returned rows are a fresh snapshot. They contain a unit only for the
---current refresh and therefore do not retain references from prior snapshots.
---@param active_units table
---@param descriptor table
---@param dependencies? table
---@return table[]
function MoodPopoverModel:build_snapshot(active_units, descriptor, dependencies)
    assert(type(active_units) == 'table', 'active_units must be a table')
    assert(type(descriptor) == 'table' and
        type(descriptor.stress_category) == 'number',
        'descriptor must contain a stress_category')

    dependencies = dependencies or default_dependencies()
    local is_valid = assert(dependencies.is_valid,
        'dependencies.is_valid is required')
    local is_citizen = assert(dependencies.is_citizen,
        'dependencies.is_citizen is required')
    local get_stress_category = assert(dependencies.get_stress_category,
        'dependencies.get_stress_category is required')
    local get_readable_name = assert(dependencies.get_readable_name,
        'dependencies.get_readable_name is required')
    local rows = {}

    for _, unit in ipairs(active_units) do
        if self:is_mood_unit(unit, is_valid, is_citizen) and
            get_stress_category(unit) == descriptor.stress_category
        then
            local id = unit.id
            if id ~= nil then
                table.insert(rows, {
                    id=id,
                    unit=unit,
                    name=tostring(get_readable_name(unit) or ''),
                })
            end
        end
    end

    table.sort(rows, function(left, right)
        local left_name = self:normalize_name(left.name)
        local right_name = self:normalize_name(right.name)
        if left_name == right_name then return left.id < right.id end
        return left_name < right_name
    end)

    return rows
end

---Builds a mood snapshot from DF's current active-unit collection.
---@param descriptor table
---@param dependencies? table
---@return table[]
function MoodPopoverModel:build_active_snapshot(descriptor, dependencies)
    dependencies = dependencies or default_dependencies()
    local get_active_units = assert(dependencies.get_active_units,
        'dependencies.get_active_units is required')
    return self:build_snapshot(get_active_units(), descriptor, dependencies)
end
