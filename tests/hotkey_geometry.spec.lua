local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local function load_geometry()
    local _, immutable_enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/utils/immutable_enum.lua')
    local environment = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/hotkeys/geometry.lua', {
            reqscript={['dwarfui/utils/immutable_enum']=immutable_enum},
        })
    return environment.HotkeyGeometry
end

local function filled_reader(rectangles)
    return function(x, y)
        for _, rect in ipairs(rectangles) do
            if x >= rect.x1 and x <= rect.x2 and
                    y >= rect.y1 and y <= rect.y2 then
                return {tile=1, ch=0, write_to_lower=true}
            end
        end
        return {tile=0, ch=32, write_to_lower=false}
    end
end

describe('DwarfUI reusable hotkey geometry', function()
    it('validates and manipulates inclusive rectangles', function()
        local geometry = load_geometry()
        local rect = geometry.validate_rect({x1=2, y1=3, x2=6, y2=8})
        assert.same({x1=2, y1=3, x2=6, y2=8}, rect)
        assert.equals(5, geometry.width(rect))
        assert.equals(6, geometry.height(rect))
        assert.is_true(geometry.contains(rect, 6, 8))
        assert.is_false(geometry.contains(rect, 7, 8))
        assert.same({x1=1, y1=5, x2=5, y2=10},
            geometry.translate(rect, -1, 2))
        assert.same({x1=0, y1=1, x2=4, y2=6},
            geometry.to_local(rect, {x=2, y=2}))
        assert.same({x1=2, y1=3, x2=10, y2=10}, geometry.union({
            rect, {x1=8, y1=7, x2=10, y2=10},
        }))
        assert.is_nil(geometry.validate_rect({x1=4, y1=2, x2=3, y2=2}))
    end)

    it('scans only the caller-provided native region', function()
        local geometry = load_geometry()
        local read_tile = filled_reader{
            {x1=1, y1=1, x2=2, y2=2},
            {x1=6, y1=1, x2=8, y2=3},
            {x1=20, y1=20, x2=22, y2=22},
        }
        local components = geometry.scan_components(
            {x1=0, y1=0, x2=10, y2=10}, read_tile)
        assert.equals(2, #components)
        assert.same({x1=1, y1=1, x2=2, y2=2, cell_count=4}, components[1])
        assert.same({x1=6, y1=1, x2=8, y2=3, cell_count=9}, components[2])
    end)

    it('does not retain sampled cells between scans', function()
        local geometry = load_geometry()
        local visible = true
        local read_tile = function(x, y)
            if visible and x >= 2 and x <= 5 and y >= 2 and y <= 3 then
                return {tile=1, ch=0, write_to_lower=true}
            end
            return {tile=0, ch=32, write_to_lower=false}
        end
        local region = {x1=0, y1=0, x2=8, y2=8}
        assert.equals(1, #geometry.scan_components(region, read_tile))
        visible = false
        assert.equals(0, #geometry.scan_components(region, read_tile))
    end)

    it('derives repeated horizontal and vertical element bounds', function()
        local geometry = load_geometry()
        local horizontal = geometry.find_repeated_strip({
            {x1=10, y1=20, x2=25, y2=23, cell_count=64},
        }, {
            expected_count=4,
            axis=geometry.HotkeyStripAxis.HORIZONTAL,
        })
        assert.same({x1=10, y1=20, x2=13, y2=23}, horizontal.elements[1])
        assert.same({x1=22, y1=20, x2=25, y2=23}, horizontal.elements[4])

        local vertical = geometry.find_repeated_strip({
            {x1=10, y1=20, x2=13, y2=27, cell_count=32},
        }, {
            expected_count=2,
            axis=geometry.HotkeyStripAxis.VERTICAL,
        })
        assert.same({x1=10, y1=24, x2=13, y2=27}, vertical.elements[2])
    end)

    it('rejects ambiguous or invalid strip candidates', function()
        local geometry = load_geometry()
        local options = {
            expected_count=2,
            axis=geometry.HotkeyStripAxis.HORIZONTAL,
        }
        local strip, error_code = geometry.find_repeated_strip({
            {x1=0, y1=0, x2=7, y2=2, cell_count=24},
            {x1=10, y1=0, x2=17, y2=2, cell_count=24},
        }, options)
        assert.is_nil(strip)
        assert.equals('ambiguous', error_code)

        strip, error_code = geometry.find_repeated_strip({
            {x1=0, y1=0, x2=6, y2=2, cell_count=21},
        }, options)
        assert.is_nil(strip)
        assert.equals('not_found', error_code)
    end)

    it('applies caller validation to components and elements', function()
        local geometry = load_geometry()
        local strip = geometry.find_repeated_strip({
            {x1=0, y1=0, x2=11, y2=2, cell_count=36},
            {x1=20, y1=0, x2=31, y2=2, cell_count=36},
        }, {
            expected_count=3,
            axis=geometry.HotkeyStripAxis.HORIZONTAL,
            component_predicate=function(component)
                return component.x1 == 20
            end,
            element_predicate=function(bounds, index)
                return index >= 1 and bounds.y2 - bounds.y1 == 2
            end,
        })
        assert.same({x1=20, y1=0, x2=23, y2=2}, strip.elements[1])
        assert.same({x1=28, y1=0, x2=31, y2=2}, strip.elements[3])
    end)

    it('creates stable signatures independent of element map iteration order',
            function()
        local geometry = load_geometry()
        local group = {x1=1, y1=2, x2=8, y2=4}
        local first = geometry.make_signature('example', group, {
            z={x1=5, y1=2, x2=8, y2=4},
            a={x1=1, y1=2, x2=4, y2=4},
        })
        local second = geometry.make_signature('example', group, {
            a={x1=1, y1=2, x2=4, y2=4},
            z={x1=5, y1=2, x2=8, y2=4},
        })
        assert.equals(first, second)
        assert.is_truthy(first:find('example', 1, true))
        assert.is_nil(geometry.make_signature('example', group, {
            bad={x1=1, y1=2, x2=0, y2=4},
        }))
    end)
end)
