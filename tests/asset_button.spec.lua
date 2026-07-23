local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local module_path =
    'src/scripts_modinstalled/dwarfui/widgets/asset_button.lua'

local function getval(value)
    if type(value) == 'function' then return value() end
    return value
end

local function row_character(row, column)
    if type(row) == 'string' then return row:sub(column, column) end
    return row[column]
end

local function asset_tile(asset, column, row)
    if not asset then return nil end
    return ('%s:%d:%d'):format(
        asset.page, asset.x + column - 1, asset.y + row - 1)
end

local function make_context(graphics_available)
    local mouse = {x=nil, y=nil}
    local specs = {}
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets({
        Widget={
            getMousePos=function(self)
                if mouse.x == nil or mouse.y == nil or
                        not self.frame_body or
                        not self.frame_body:inClipGlobalXY(mouse.x, mouse.y) then
                    return nil
                end
                return self.frame_body:localXY(mouse.x, mouse.y)
            end,
        },
    }, default_nil)
    widgets.Widget.ATTRS{
        visible=true,
        enabled=true,
        disabled=false,
        tooltip=default_nil,
    }
    widgets.Label.makeButtonLabelText = function(spec)
        table.insert(specs, spec)
        local function graphics_tile(asset, column, row)
            if graphics_available == false then return nil end
            return asset_tile(asset, column, row)
        end
        local result = {}
        for row_index, row in ipairs(spec.chars) do
            local rendered_row = {}
            for column=1,#row do
                table.insert(rendered_row, {
                    ch=row_character(row, column),
                    ch_hover=spec.chars_hover and
                        row_character(spec.chars_hover[row_index], column) or
                        row_character(row, column),
                    tile=graphics_tile(spec.asset, column, row_index),
                    tile_hover=graphics_tile(
                        spec.asset_hover or spec.asset, column, row_index),
                })
            end
            table.insert(result, rendered_row)
        end
        return result
    end

    local _, asset_button = module_loader.load(repo_root, module_path, {
        globals={
            DEFAULT_NIL=default_nil,
            defclass=widget_harness.defclass,
        },
        require_modules={
            utils={getval=getval},
            ['gui.widgets']=widgets,
        },
        reqscript={
            ['dwarfui/widget_extensions']={},
        },
    })
    return {
        AssetButton=asset_button.AssetButton,
        mouse=mouse,
        specs=specs,
        widgets=widgets,
    }
end

local function expect_error(expected, callback)
    local ok, err = pcall(callback)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find(expected, 1, true), tostring(err))
end

describe('DwarfUI AssetButton', function()
    it('maps an arbitrary rectangular asset and matching classic grids',
            function()
        local context = make_context()
        local asset = {page='INTERFACE_BITS', x=10, y=20}
        local asset_hover = {page='INTERFACE_BITS', x=30, y=40}
        local pens = {{1, 2, 3}, {4, 5, 6}}
        local pens_hover = {{7, 8, 9}, {10, 11, 12}}
        local button = context.AssetButton{
            frame={l=2, t=3},
            asset=asset,
            asset_hover=asset_hover,
            chars={{'a', 'b', 'c'}, 'def'},
            chars_hover={{'A', 'B', 'C'}, 'DEF'},
            pens=pens,
            pens_hover=pens_hover,
            tooltip='Action',
            on_activate=function() end,
        }

        assert.same({2, 3, 3, 2},
            {button.frame.l, button.frame.t, button.frame.w, button.frame.h})
        assert.equals('Action', button.tooltip)
        assert.equals(1, #context.specs)
        local spec = context.specs[1]
        assert.is.equal(asset, spec.asset)
        assert.is.equal(asset_hover, spec.asset_hover)
        assert.is.equal(pens, spec.pens)
        assert.is.equal(pens_hover, spec.pens_hover)
        assert.same({
            ch='f',
            ch_hover='F',
            tile='INTERFACE_BITS:12:21',
            tile_hover='INTERFACE_BITS:32:41',
        }, button.text[2][3])
    end)

    it('renders a classic fallback without requiring a graphics asset',
            function()
        local context = make_context(false)
        local button = context.AssetButton{
            asset={page='UNAVAILABLE', x=0, y=0},
            chars={'>X ', '   ', '   '},
            chars_hover={'>X!', '   ', '   '},
            on_activate=function() end,
        }

        assert.same({3, 3}, {button.frame.w, button.frame.h})
        assert.same({
            ch='X',
            ch_hover='X',
            tile=nil,
            tile_hover=nil,
        }, button.text[1][2])
        assert.equals('!', button.text[1][3].ch_hover)
    end)

    it('rejects invalid grids, assets, callbacks, and frame sizes', function()
        local context = make_context()
        local valid = {
            chars={'abc', 'def'},
            on_activate=function() end,
        }

        expect_error('on_activate must be a function', function()
            context.AssetButton{chars={'x'}}
        end)
        expect_error('must be a non-empty row table', function()
            context.AssetButton{
                chars={},
                on_activate=function() end,
            }
        end)
        expect_error('row 2 has width 2; expected 3', function()
            context.AssetButton{
                chars={'abc', 'de'},
                on_activate=function() end,
            }
        end)
        expect_error('cell 2,1 must be one byte', function()
            context.AssetButton{
                chars={{'a', 'bc'}},
                on_activate=function() end,
            }
        end)
        expect_error('row 1 must contain contiguous cells', function()
            context.AssetButton{
                chars={{[1]='a', [3]='c'}},
                on_activate=function() end,
            }
        end)
        expect_error('chars_hover has width 2; expected 3', function()
            context.AssetButton{
                chars=valid.chars,
                chars_hover={'ab', 'cd'},
                on_activate=valid.on_activate,
            }
        end)
        expect_error('asset.page must be a non-empty string', function()
            context.AssetButton{
                chars=valid.chars,
                asset={page='', x=0, y=0},
                on_activate=valid.on_activate,
            }
        end)
        expect_error('asset.x must be an integer', function()
            context.AssetButton{
                chars=valid.chars,
                asset={page='PAGE', x=0.5, y=0},
                on_activate=valid.on_activate,
            }
        end)
        expect_error('asset_hover requires AssetButton.asset', function()
            context.AssetButton{
                chars=valid.chars,
                asset_hover={page='PAGE', x=0, y=0},
                on_activate=valid.on_activate,
            }
        end)
        expect_error('frame width is 4; expected 3', function()
            context.AssetButton{
                frame={w=4},
                chars=valid.chars,
                on_activate=valid.on_activate,
            }
        end)
        expect_error('frame height is 3; expected 2', function()
            context.AssetButton{
                frame={h=3},
                chars=valid.chars,
                on_activate=valid.on_activate,
            }
        end)
    end)

    it('activates across every hit-test edge and passes other input through',
            function()
        local context = make_context()
        local activations = 0
        local button = context.AssetButton{
            frame={l=3, t=4},
            chars={'ab', 'cd'},
            on_activate=function() activations = activations + 1 end,
        }
        button:updateLayout(widget_harness.rect(0, 0, 20, 20))

        for _, point in ipairs({
                {3, 4},
                {4, 4},
                {3, 5},
                {4, 5},
            }) do
            context.mouse.x, context.mouse.y = point[1], point[2]
            assert.is_true(button:onInput({_MOUSE_L=true}))
        end
        assert.equals(4, activations)

        for _, point in ipairs({
                {2, 4},
                {5, 4},
                {3, 3},
                {3, 6},
            }) do
            context.mouse.x, context.mouse.y = point[1], point[2]
            assert.is_false(button:onInput({_MOUSE_L=true}))
        end
        context.mouse.x, context.mouse.y = 3, 4
        assert.is_false(button:onInput({_MOUSE_R=true}))
        assert.is_false(button:onInput({CONTEXT_SCROLL_DOWN=true}))
        assert.is_false(button:onInput(nil))
        assert.equals(4, activations)
    end)

    it('applies hover and activation guards to dynamic widget state',
            function()
        local context = make_context()
        local visible, enabled, disabled = true, true, false
        local activations = 0
        local button = context.AssetButton{
            chars={'x'},
            visible=function() return visible end,
            enabled=function() return enabled end,
            disabled=function() return disabled end,
            on_activate=function() activations = activations + 1 end,
        }
        button:updateLayout(widget_harness.rect(0, 0, 5, 5))
        context.mouse.x, context.mouse.y = 0, 0

        assert.is_true(button:shouldHover())
        assert.is_true(button:onInput({_MOUSE_L=true}))

        enabled = false
        assert.is_false(button:shouldHover())
        assert.is_false(button:onInput({_MOUSE_L=true}))
        enabled, disabled = true, true
        assert.is_false(button:shouldHover())
        assert.is_false(button:onInput({_MOUSE_L=true}))
        disabled, visible = false, false
        assert.is_false(button:shouldHover())
        assert.is_false(button:onInput({_MOUSE_L=true}))
        assert.equals(1, activations)
    end)

    it('keeps differently sized button instances and callbacks isolated',
            function()
        local context = make_context()
        local first_activations, second_activations = 0, 0
        local first = context.AssetButton{
            frame={l=0, t=0},
            chars={'1'},
            on_activate=function()
                first_activations = first_activations + 1
            end,
        }
        local second = context.AssetButton{
            frame={l=5, t=2},
            asset={page='SECOND', x=7, y=9},
            chars={'abc', 'def'},
            on_activate=function()
                second_activations = second_activations + 1
            end,
        }
        local parent = widget_harness.rect(0, 0, 20, 10)
        first:updateLayout(parent)
        second:updateLayout(parent)

        assert.same({1, 1}, {first.frame.w, first.frame.h})
        assert.same({3, 2}, {second.frame.w, second.frame.h})
        assert.is_not.equal(first.frame, second.frame)
        context.mouse.x, context.mouse.y = 0, 0
        assert.is_true(first:onInput({_MOUSE_L=true}))
        assert.is_false(second:onInput({_MOUSE_L=true}))
        context.mouse.x, context.mouse.y = 7, 3
        assert.is_false(first:onInput({_MOUSE_L=true}))
        assert.is_true(second:onInput({_MOUSE_L=true}))

        assert.same({1, 1}, {first_activations, second_activations})
        assert.is_nil(context.specs[1].asset)
        assert.equals('SECOND', context.specs[2].asset.page)
    end)
end)
