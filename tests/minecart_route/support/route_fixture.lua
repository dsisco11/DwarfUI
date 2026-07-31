--@ module=true

---Creates and removes disposable hauling routes for native minecart tests.
---@class dwarfui.MinecartRouteFixture
MinecartRouteFixture = {}

---Returns the center of the visible dwarfmode map area on its current z-level.
---@return {x: integer, y: integer, z: integer}
local function map_center_position()
    local corner = df.global.world.viewport.corner
    local dims = dfhack.gui.getDwarfmodeViewDims()
    return {
        x=corner.x + (dims.map_x2 - dims.map_x1 + 1) // 2,
        y=corner.y + (dims.map_y2 - dims.map_y1 + 1) // 2,
        z=df.global.window_z,
    }
end

---Returns a valid map position one z-level away from the current viewport.
---@return {x: integer, y: integer, z: integer}
local function secondary_position()
    local position = map_center_position()
    local z_count = df.global.world.map.z_count
    local z = df.global.window_z + 1 < z_count and
        df.global.window_z + 1 or df.global.window_z - 1
    assert(z >= 0, 'TestWorld 01 must provide at least two z-levels')
    return {x=position.x, y=position.y, z=z}
end

---Adds one route with one stop to the native hauling data.
---@param hauling df.hauling_handlerst
---@param name string
---@param pos {x: integer, y: integer, z: integer}
---@return df.hauling_route
local function add_route(hauling, name, pos)
    hauling.routes:insert('#', {
        new=df.hauling_route,
        id=hauling.next_id,
        name=name,
    })
    hauling.next_id = hauling.next_id + 1
    local route = hauling.routes[#hauling.routes - 1]
    route.stops:insert('#', {
        new=df.hauling_stop,
        id=1,
        name=name .. ' stop',
        pos=pos,
    })
    return route
end

---Creates two distinct routes required by the native minecart interaction tests.
---@return {hauling: df.hauling_handlerst, routes: df.hauling_route[], next_id: integer}
function MinecartRouteFixture.create()
    local hauling = assert(df.global.plotinfo.hauling,
        'native Hauling state is unavailable')
    local center = map_center_position()
    local fixture = {
        hauling=hauling,
        routes={},
        next_id=hauling.next_id,
    }
    fixture.routes[1] = add_route(hauling, 'DwarfUI test route A',
        secondary_position())
    for index=2,16 do
        fixture.routes[index] = add_route(hauling,
            ('DwarfUI test route %d'):format(index), {
                x=center.x,
                y=center.y,
                z=center.z,
            })
    end
    return fixture
end

---Removes every route created by `create` and restores the original ID counter.
---@param fixture {hauling: df.hauling_handlerst, routes: df.hauling_route[], next_id: integer}|nil
function MinecartRouteFixture.destroy(fixture)
    if not fixture then return end
    local routes = fixture.hauling.routes
    for index=#routes - 1,0,-1 do
        local route = routes[index]
        for _, owned in ipairs(fixture.routes) do
            if route == owned then
                routes:erase(index)
                break
            end
        end
    end
    fixture.hauling.next_id = fixture.next_id
end

return MinecartRouteFixture
