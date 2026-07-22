local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Creates a minimal callable class for pure-model tests.
---@param class table|nil
---@return table
local function test_defclass(class)
    class = class or {}
    return setmetatable(class, {__call=function(class_table, attributes)
        local instance = attributes or {}
        setmetatable(instance, {__index=class_table})
        if instance.init then instance:init() end
        return instance
    end})
end

local route_environment = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/minecart_route.lua', {
        globals={defclass=test_defclass},
    })

local MinecartRouteMenuLayout = route_environment.MinecartRouteMenuLayout
local MinecartRouteSelection = route_environment.MinecartRouteSelection
local MinecartRouteMarkerProjection =
    route_environment.MinecartRouteMarkerProjection

---Creates a zero-based vector fixture.
---@param values table[]
---@return table
local function zero_vector(values)
    local vector = {}
    for index, value in ipairs(values) do vector[index - 1] = value end
    return vector
end

---Creates native-style flattened route and stop row fixtures.
---@return table hauling
---@return table[] routes
local function route_fixture()
    local first = {id=10, name='Duplicate'}
    local second = {id=11, name='Duplicate'}
    local first_stop = {id=1, name='Stop'}
    local second_stop = {id=1, name='Stop'}
    return {
        scroll_position=0,
        view_routes=zero_vector({first, first, second, second}),
        view_stops=zero_vector({false, first_stop, false, second_stop}),
    }, {first, second}
end

---Creates a viewport double that exposes only the documented projection API.
---@param x1 integer
---@param y1 integer
---@param z integer
---@param width integer
---@param height integer
---@return table
local function viewport_fixture(x1, y1, z, width, height)
    local calls = {visible=0, visible_xy=0, tile_to_screen=0}
    local viewport = {x1=x1, y1=y1, z=z, width=width, height=height,
        calls=calls}

    function viewport:isVisible(pos)
        self.calls.visible = self.calls.visible + 1
        return pos.x >= self.x1 and pos.x < self.x1 + self.width and
            pos.y >= self.y1 and pos.y < self.y1 + self.height and
            pos.z == self.z
    end

    function viewport:isVisibleXY(pos)
        self.calls.visible_xy = self.calls.visible_xy + 1
        return pos.x >= self.x1 and pos.x < self.x1 + self.width and
            pos.y >= self.y1 and pos.y < self.y1 + self.height
    end

    function viewport:tileToScreen(pos)
        self.calls.tile_to_screen = self.calls.tile_to_screen + 1
        return {x=pos.x - self.x1, y=pos.y - self.y1, z=pos.z - self.z}
    end

    return viewport
end

---Creates a native-style selected route with a zero-based stop vector.
---@param stops table[]
---@return table
local function selected_route(stops)
    return {id=99, stops=zero_vector(stops)}
end

describe('DwarfUI minecart route menu layout', function()
    it('maps the complete three-cell route header to row zero', function()
        local hauling, routes = route_fixture()
        local layout = MinecartRouteMenuLayout{}

        for mouse_y=10,12 do
            for _, mouse_x in ipairs({0, 6, 71}) do
                local row = layout:resolve_row(mouse_x, mouse_y, hauling,
                    'dwarfmode/Hauling')
                assert.equals(0, row.index)
                assert.is_equal(routes[1], row.route)
                assert.is_nil(row.stop)
                assert.is_true(row.is_route_header)
            end
        end
    end)

    it('maps a stop row to its owning route', function()
        local hauling, routes = route_fixture()
        local row = MinecartRouteMenuLayout{}:resolve_row(6, 14, hauling,
            'dwarfmode/Hauling')

        assert.equals(1, row.index)
        assert.is_equal(routes[1], row.route)
        assert.equals(1, row.stop.id)
        assert.is_false(row.is_route_header)
    end)

    it('adds native scrolling to the visible row offset', function()
        local routes = {}
        local stops = {}
        for index=0,7 do
            routes[index] = {id=100 + index}
            stops[index] = index % 2 == 0 and false or {id=index}
        end
        local row = MinecartRouteMenuLayout{}:resolve_row(20, 14, {
            scroll_position=5,
            view_routes=routes,
            view_stops=stops,
        }, 'dwarfmode/Hauling')

        assert.equals(6, row.index)
        assert.equals(106, row.route.id)
    end)

    it('rejects pointers outside every list boundary', function()
        local hauling = route_fixture()
        local layout = MinecartRouteMenuLayout{}
        local points = {
            {-1, 10}, {72, 10}, {0, 9}, {nil, 10}, {0, nil},
        }

        for _, point in ipairs(points) do
            assert.is_nil(layout:resolve_row(point[1], point[2], hauling,
                'dwarfmode/Hauling'))
        end
    end)

    it('rejects invalid rows, scrolling, and missing vectors', function()
        local hauling = route_fixture()
        local layout = MinecartRouteMenuLayout{}

        assert.is_nil(layout:resolve_row(6, 40, hauling,
            'dwarfmode/Hauling'))
        assert.is_nil(layout:resolve_row(6, 10, {
            scroll_position=-1, view_routes=hauling.view_routes,
        }, 'dwarfmode/Hauling'))
        assert.is_nil(layout:resolve_row(6, 10, {}, 'dwarfmode/Hauling'))
    end)

    it('fails closed for base and nested non-Hauling contexts', function()
        local hauling = route_fixture()
        local layout = MinecartRouteMenuLayout{}

        for _, focus in ipairs({
                'dwarfmode/Default',
                'dwarfmode/Hauling/DefineStop',
                'dwarfmode/Hauling/AssignVehicle',
            }) do
            assert.is_nil(layout:resolve_row(6, 10, hauling, focus))
        end
        assert.is_nil(layout:resolve_row(6, 10, hauling, nil))
    end)

    it('supports injected geometry without changing row semantics', function()
        local hauling, routes = route_fixture()
        local layout = MinecartRouteMenuLayout{
            list_x1=20, list_x2=40, first_row_top=30, row_height=4,
        }
        local row = layout:resolve_row(20, 34, hauling,
            'dwarfmode/Hauling')

        assert.equals(1, row.index)
        assert.is_equal(routes[1], row.route)
    end)
end)

describe('DwarfUI minecart route selection', function()
    it('selects route headers and passes the click through', function()
        local hauling, routes = route_fixture()
        local selection = MinecartRouteSelection{}

        assert.is_false(selection:observe_input({_MOUSE_L=true}, 6, 11,
            hauling, 'dwarfmode/Hauling'))
        assert.equals(routes[1].id, selection:get_selected_route_id())
    end)

    it('selects the owning route from a stop row after scrolling', function()
        local hauling, routes = route_fixture()
        hauling.scroll_position = 2
        local selection = MinecartRouteSelection{}

        assert.is_false(selection:observe_input({_MOUSE_L=true}, 6, 14,
            hauling, 'dwarfmode/Hauling'))
        assert.equals(routes[2].id, selection:get_selected_route_id())
    end)

    it('preserves selection for unhandled input and invalid pointers', function()
        local hauling, routes = route_fixture()
        local selection = MinecartRouteSelection{selected_route_id=routes[1].id}

        assert.is_false(selection:observe_input({CURSOR_DOWN=true}, 6, 11,
            hauling, 'dwarfmode/Hauling'))
        assert.is_false(selection:observe_input({_MOUSE_L=true}, 80, 11,
            hauling, 'dwarfmode/Hauling'))
        assert.is_false(selection:observe_input({_MOUSE_L=true}, 6, 11,
            hauling, 'dwarfmode/Hauling/DefineStop'))
        assert.equals(routes[1].id, selection:get_selected_route_id())
    end)

    it('uses numeric identity when route and stop names are duplicated', function()
        local hauling, routes = route_fixture()
        local selection = MinecartRouteSelection{}

        selection:observe_input({_MOUSE_L=true}, 6, 20, hauling,
            'dwarfmode/Hauling')

        assert.equals('Duplicate', routes[1].name)
        assert.equals('Duplicate', routes[2].name)
        assert.equals('Stop', hauling.view_stops[1].name)
        assert.equals('Stop', hauling.view_stops[3].name)
        assert.equals(11, selection:get_selected_route_id())
    end)

    it('resolves zero-based native vectors and standard Lua sequences', function()
        local first = {id=0}
        local second = {id=2}
        local selection = MinecartRouteSelection{selected_route_id=0}

        assert.is_equal(first, selection:resolve_selected_route(
            zero_vector({first, second})))
        selection.selected_route_id = 2
        assert.is_equal(second, selection:resolve_selected_route({first, second}))
    end)

    it('clears a selected ID when its native route no longer exists', function()
        local selection = MinecartRouteSelection{selected_route_id=99}

        assert.is_nil(selection:resolve_selected_route(zero_vector({{id=1}})))
        assert.is_nil(selection:get_selected_route_id())
    end)

    it('rejects routes without numeric IDs and supports explicit clearing', function()
        local selection = MinecartRouteSelection{selected_route_id=5}

        assert.is_false(selection:select_route(nil))
        assert.is_false(selection:select_route({id='5'}))
        assert.equals(5, selection:get_selected_route_id())
        selection:clear()
        assert.is_nil(selection:get_selected_route_id())
    end)
end)

describe('DwarfUI minecart route marker projection', function()
    it('projects same-z stops exactly onto their map tiles in route order',
            function()
        local viewport = viewport_fixture(10, 20, 5, 20, 10)
        local markers = MinecartRouteMarkerProjection{}:project(selected_route({
            {id=7, name='North', pos={x=12, y=23, z=5}},
            {id=8, name='South', pos={x=15, y=25, z=5}},
        }), viewport)

        assert.equals(2, #markers)
        assert.equals(7, markers[1].stop_id)
        assert.equals(1, markers[1].display_index)
        assert.same({x=12, y=23, z=5}, markers[1].world_pos)
        assert.same({x=2, y=3, z=0}, markers[1].screen_pos)
        assert.equals(0, markers[1].z_delta)
        assert.equals('same_z', markers[1].marker_kind)
        assert.equals(string.char(15), markers[1].marker_glyph)
        assert.equals('North', markers[1].label)
        assert.equals(8, markers[2].stop_id)
        assert.equals(2, markers[2].display_index)
        assert.equals(2, viewport.calls.visible)
        assert.equals(0, viewport.calls.visible_xy)
        assert.equals(2, viewport.calls.tile_to_screen)
    end)

    it('marks visible above and below stops as directional projections',
            function()
        local viewport = viewport_fixture(0, 0, 10, 20, 10)
        local markers = MinecartRouteMarkerProjection{}:project(selected_route({
            {id=1, name='Above', pos={x=3, y=4, z=12}},
            {id=2, name='Below', pos={x=6, y=4, z=7}},
        }), viewport)

        assert.equals('above', markers[1].marker_kind)
        assert.equals(string.char(24), markers[1].marker_glyph)
        assert.equals(2, markers[1].z_delta)
        assert.equals('Above (z+2)', markers[1].label)
        assert.equals('below', markers[2].marker_kind)
        assert.equals(string.char(25), markers[2].marker_glyph)
        assert.equals(-3, markers[2].z_delta)
        assert.equals('Below (z-3)', markers[2].label)
        assert.equals(0, viewport.calls.visible)
        assert.equals(2, viewport.calls.visible_xy)
    end)

    it('does not emit stops outside the map viewport', function()
        local viewport = viewport_fixture(10, 10, 3, 8, 6)
        local markers = MinecartRouteMarkerProjection{}:project(selected_route({
            {id=1, name='Past edge', pos={x=18, y=10, z=3}},
            {id=2, name='Other z', pos={x=9, y=10, z=4}},
        }), viewport)

        assert.equals(0, #markers)
        assert.equals(1, viewport.calls.visible)
        assert.equals(1, viewport.calls.visible_xy)
        assert.equals(0, viewport.calls.tile_to_screen)
    end)

    it('keeps full labels inside both map edges', function()
        local viewport = viewport_fixture(0, 0, 0, 12, 4)
        local markers = MinecartRouteMarkerProjection{}:project(selected_route({
            {id=1, name='Left', pos={x=0, y=1, z=0}},
            {id=2, name='Right', pos={x=11, y=2, z=0}},
        }), viewport)

        assert.equals(1, markers[1].label_x)
        assert.equals(6, markers[2].label_x)
        for _, marker in ipairs(markers) do
            assert.is_true(marker.label_x >= 0)
            assert.is_true(marker.label_x + #marker.label <= viewport.width)
            assert.is_true(marker.label_y >= 0)
            assert.is_true(marker.label_y < viewport.height)
        end
    end)

    it('truncates long labels only when neither side can contain them',
            function()
        local viewport = viewport_fixture(0, 0, 0, 9, 3)
        local marker = MinecartRouteMarkerProjection{}:project(selected_route({
            {id=1, name='Very long stop name', pos={x=4, y=1, z=0}},
        }), viewport)[1]

        assert.equals('Very', marker.label)
        assert.equals(5, marker.label_x)
        assert.is_true(marker.label_x + #marker.label <= viewport.width)
    end)

    it('keeps empty names visible and copies mutable native positions',
            function()
        local viewport = viewport_fixture(0, 0, 0, 20, 5)
        local pos = {x=2, y=2, z=0}
        local marker = MinecartRouteMarkerProjection{}:project(selected_route({
            {id=1, name='', pos=pos},
        }), viewport)[1]
        pos.x = 17

        assert.equals('', marker.name)
        assert.equals('(unnamed)', marker.label)
        assert.equals(2, marker.world_pos.x)
    end)

    it('resolves duplicate-position label collisions without moving markers',
            function()
        local viewport = viewport_fixture(0, 0, 0, 20, 4)
        local markers = MinecartRouteMarkerProjection{}:project(selected_route({
            {id=1, name='First', pos={x=5, y=1, z=0}},
            {id=2, name='Second', pos={x=5, y=1, z=0}},
        }), viewport)

        assert.same({x=5, y=1, z=0}, markers[1].screen_pos)
        assert.same({x=5, y=1, z=0}, markers[2].screen_pos)
        assert.equals(1, markers[1].label_y)
        assert.equals(2, markers[2].label_y)
    end)
end)

describe('DwarfUI minecart route header indicator', function()
    it('finds a selected route header after native list scrolling', function()
        local hauling, routes = route_fixture()
        hauling.scroll_position = 2
        local layout = MinecartRouteMenuLayout{}

        assert.equals(10, layout:find_route_header_y(hauling, routes[2].id,
            'dwarfmode/Hauling'))
        assert.is_nil(layout:find_route_header_y(hauling, routes[1].id,
            'dwarfmode/Hauling'))
    end)
end)
