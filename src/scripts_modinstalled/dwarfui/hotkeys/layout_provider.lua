--@ module=true

local immutable_enum = reqscript('dwarfui/utils/immutable_enum')
local geometry = reqscript('dwarfui/hotkeys/geometry')

---@enum dwarfui.HotkeyGeometrySourceKind
HotkeyGeometrySourceKind = immutable_enum.define({
    NATIVE_CONTROL=1,
    RENDERED_TILES=2,
    CUSTOM=3,
}, 'HotkeyGeometrySourceKind')

---@enum dwarfui.HotkeyGroupState
HotkeyGroupState = immutable_enum.define({
    INACTIVE=1,
    READY=2,
    UNAVAILABLE=3,
    AMBIGUOUS=4,
}, 'HotkeyGroupState')

---@class dwarfui.HotkeyLayoutProvider
HotkeyLayoutProvider = {}
HotkeyLayoutProvider.HotkeyGeometrySourceKind = HotkeyGeometrySourceKind
HotkeyLayoutProvider.HotkeyGroupState = HotkeyGroupState

local function failure(state, reason)
    return nil, {state=state, reason=reason}
end

---Creates a typed provider failure result.
---@param state dwarfui.HotkeyGroupState
---@param reason string|nil
---@return nil
---@return dwarfui.HotkeyLayoutFailure
function HotkeyLayoutProvider.failure(state, reason)
    if state ~= HotkeyGroupState.INACTIVE and state ~= HotkeyGroupState.UNAVAILABLE and
            state ~= HotkeyGroupState.AMBIGUOUS then
        state = HotkeyGroupState.UNAVAILABLE
    end
    return failure(state, reason)
end

---Validates and copies a complete provider layout at the module boundary.
---@param definition dwarfui.HotkeyGroupDefinition
---@param layout table|nil
---@return dwarfui.HotkeyGroupLayout|nil
---@return dwarfui.HotkeyLayoutFailure|nil
function HotkeyLayoutProvider.validate_result(definition, layout)
    if type(definition) ~= 'table' or type(definition.group_id) ~= 'string' or
            definition.group_id == '' or type(layout) ~= 'table' or
            layout.group_id ~= definition.group_id then
        return failure(HotkeyGroupState.UNAVAILABLE, 'malformed_layout')
    end
    local bounds = geometry.validate_rect(layout.bounds)
    if not bounds or type(layout.elements) ~= 'table' or
            type(layout.signature) ~= 'string' or layout.signature == '' then
        return failure(HotkeyGroupState.UNAVAILABLE, 'malformed_layout')
    end
    local elements = {}
    for element_id, element in pairs(layout.elements) do
        local element_bounds = geometry.validate_rect(element and element.bounds or element)
        if type(element_id) ~= 'string' or element_id == '' or not element_bounds or
                not geometry.contains(bounds, element_bounds.x1, element_bounds.y1) or
                not geometry.contains(bounds, element_bounds.x2, element_bounds.y2) then
            return failure(HotkeyGroupState.UNAVAILABLE, 'invalid_element')
        end
        elements[element_id] = {element_id=element_id, bounds=element_bounds}
    end
    if next(elements) == nil then
        return failure(HotkeyGroupState.UNAVAILABLE, 'missing_elements')
    end
    return {
        group_id=definition.group_id,
        bounds=bounds,
        elements=elements,
        signature=layout.signature,
    }
end

---Invokes a provider and contains malformed results or provider exceptions.
---@param provider dwarfui.HotkeyLayoutProvider|function
---@param context dwarfui.HotkeySamplingContext
---@param definition dwarfui.HotkeyGroupDefinition
---@return dwarfui.HotkeyGroupLayout|nil
---@return dwarfui.HotkeyLayoutFailure|nil
function HotkeyLayoutProvider.invoke(provider, context, definition)
    if type(provider) ~= 'function' then
        return failure(HotkeyGroupState.UNAVAILABLE, 'missing_provider')
    end
    local ok, layout, provider_failure = pcall(provider, context, definition)
    if not ok then return failure(HotkeyGroupState.UNAVAILABLE, 'provider_error') end
    if provider_failure then return nil, provider_failure end
    return HotkeyLayoutProvider.validate_result(definition, layout)
end

local function stable_extra(value)
    if value == nil then return '' end
    if type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' then
        return tostring(value)
    end
    if type(value) ~= 'table' then return nil end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        local encoded = stable_extra(value[key])
        if not encoded then return nil end
        parts[#parts + 1] = tostring(key) .. '=' .. encoded
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

---Builds a read-only provider from rendered connected components.
---@param options table
---@return function
function HotkeyLayoutProvider.rendered_strip(options)
    options = options or {}
    return function(context, definition)
        local region = type(options.search_region) == 'function' and
            options.search_region(context, definition) or options.search_region
        if not region or type(context) ~= 'table' or type(context.read_tile) ~= 'function' then
            return failure(HotkeyGroupState.UNAVAILABLE, 'missing_sampling_context')
        end
        local components = geometry.scan_components(region, context.read_tile, options.tile_predicate)
        local strip, error_code = geometry.find_repeated_strip(components, {
            expected_count=options.expected_count,
            axis=options.axis,
            component_predicate=options.component_predicate,
            element_predicate=options.element_predicate,
        })
        if not strip then
            return failure(error_code == 'ambiguous' and HotkeyGroupState.AMBIGUOUS or
                HotkeyGroupState.UNAVAILABLE, error_code)
        end
        local ordered = type(options.element_order) == 'function' and
            options.element_order(strip, definition) or strip.elements
        if type(ordered) ~= 'table' then return failure(HotkeyGroupState.UNAVAILABLE, 'invalid_order') end
        local elements = {}
        for index, element_id in ipairs(options.element_ids or {}) do
            local bounds = ordered[index]
            if not bounds then return failure(HotkeyGroupState.UNAVAILABLE, 'incomplete_layout') end
            elements[element_id] = {element_id=element_id, bounds=bounds}
        end
        local extra = stable_extra(type(options.signature_data) == 'function' and
            options.signature_data(context, definition, strip) or options.signature_data)
        if extra == nil then return failure(HotkeyGroupState.UNAVAILABLE, 'invalid_signature_data') end
        local signature_elements = {}
        for element_id, element in pairs(elements) do
            signature_elements[element_id] = element.bounds
        end
        local signature = geometry.make_signature(definition.group_id, strip.bounds, signature_elements)
        if not signature then return failure(HotkeyGroupState.UNAVAILABLE, 'invalid_signature') end
        return {group_id=definition.group_id, bounds=strip.bounds, elements=elements,
            signature=signature .. '|' .. extra}
    end
end

---Builds a provider for native structures or explicitly identified widget roots.
---@param options table
---@return function
function HotkeyLayoutProvider.native_control(options)
    options = options or {}
    return function(context, definition)
        if type(options.locate) ~= 'function' then
            return failure(HotkeyGroupState.UNAVAILABLE, 'missing_locator')
        end
        local root = options.locate(context, definition)
        if not root then return failure(HotkeyGroupState.UNAVAILABLE, 'not_found') end
        local is_container = options.is_widget_container
        if not is_container then
            is_container = function(value)
                return df and df.widget_container and df.widget_container:is_instance(value) or false
            end
        end
        local extracted
        if is_container(root) and type(options.walk_widgets) == 'function' then
            extracted = options.walk_widgets(root, context, definition)
        elseif type(options.extract) == 'function' then
            extracted = options.extract(root, context, definition)
        else
            return failure(HotkeyGroupState.UNAVAILABLE, 'missing_extractor')
        end
        if type(extracted) ~= 'table' then return failure(HotkeyGroupState.UNAVAILABLE, 'invalid_extraction') end
        local bounds = extracted.bounds or geometry.union((function()
            local list = {}
            for _, element in pairs(extracted.elements or extracted) do
                list[#list + 1] = element.bounds or element
            end
            return list
        end)())
        local native_elements = {}
        for element_id, element in pairs(extracted.elements or extracted) do
            native_elements[element_id] = element.bounds or element
        end
        local signature_data = type(options.signature_data) == 'function' and
            options.signature_data(root, context, definition, extracted) or options.signature_data
        local extra = stable_extra(signature_data)
        local signature = bounds and geometry.make_signature(definition.group_id, bounds, native_elements)
        if not bounds or not signature or not extra then
            return failure(HotkeyGroupState.UNAVAILABLE, 'malformed_extraction')
        end
        return {group_id=definition.group_id, bounds=bounds,
            elements=extracted.elements or extracted, signature=signature .. '|' .. extra}
    end
end
