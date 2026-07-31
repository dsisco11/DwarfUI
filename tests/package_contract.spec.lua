local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local separator = package.config:sub(1, 1)
local shipped_modules = {
    'dwarfui/module_registry.lua',
    'dwarfui/class.lua',
    'dwarfui/text.lua',
    'dwarfui/utils/numbers.lua',
    'dwarfui/utils/immutable_enum.lua',
    'dwarfui/context_menu/definition.lua',
    'dwarfui/context_menu/target.lua',
    'dwarfui/widget_extensions.lua',
    'dwarfui/widgets/asset_button.lua',
    'dwarfui/widgets/hover_action_rail.lua',
    'dwarfui/pointer.lua',
    'dwarfui/pointer_poller.lua',
    'dwarfui/tooltip_root_resolver.lua',
    'dwarfui/tooltip_target.lua',
    'dwarfui/tooltip_target_detector.lua',
    'dwarfui/tooltip_map_target.lua',
    'dwarfui/tooltip_service.lua',
    'dwarfui/tooltip_render_hook.lua',
    'dwarfui/minecart_route.lua',
    'dwarfui/mood_popover.lua',
    'dwarfui/popover.lua',
    'dwarfui/tooltip.lua',
    'dwarfui/tooltip_registration.lua',
    'dwarfui/unit_card_task.lua',
}

local mood_popover_payload = {
    registration='scripts_modinstalled/dwarfui-mood-popover.lua',
    model='scripts_modinstalled/dwarfui/mood_popover.lua',
    widget='scripts_modinstalled/dwarfui/popover.lua',
}

local minecart_route_payload = {
    registration='scripts_modinstalled/dwarfui-minecart-route-markers.lua',
    model='scripts_modinstalled/dwarfui/minecart_route.lua',
}

local function source_path(relative_path)
    return repo_root .. separator .. 'src' .. separator ..
        relative_path:gsub('/', separator)
end

local function read_source(relative_path)
    local file = assert(io.open(source_path(relative_path), 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

---Reads one repository file as binary text.
---@param relative_path string
---@return string
local function read_repository_file(relative_path)
    local file = assert(io.open(repo_root .. separator ..
        relative_path:gsub('/', separator), 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

local function contains(text, expected)
    assert.is_truthy(text:find(expected, 1, true))
end

---Returns the normalized target contract needed by isolated module loads.
---@return table target_types
local function tooltip_target_stub()
    return {
        TooltipTargetKind={WIDGET=1, MAP_TILE=2},
        TooltipPointerObservationKind={TARGET=1, BLOCKED=2, MISS=3},
        is_adapter=function() return false end,
        adapt_widget=function() return {} end,
        adapt_map_tile=function() return {} end,
    }
end

local function load_public_module(package_path)
    local options
    if package_path ==
            'scripts_modinstalled/dwarfui/context_menu/definition.lua' then
        local _, numbers = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/utils/numbers.lua')
        options = {
            reqscript={
                ['dwarfui/utils/numbers']=numbers,
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/context_menu/target.lua' then
        local _, numbers = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/utils/numbers.lua')
        local _, immutable_enum = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/utils/immutable_enum.lua')
        local _, definitions = module_loader.load(
            repo_root,
            'src/scripts_modinstalled/dwarfui/context_menu/definition.lua', {
                reqscript={
                    ['dwarfui/utils/numbers']=numbers,
                },
            })
        options = {
            reqscript={
                ['dwarfui/context_menu/definition']=definitions,
                ['dwarfui/utils/immutable_enum']=immutable_enum,
                ['dwarfui/utils/numbers']=numbers,
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/widget_extensions.lua' then
        local widget_harness = require('support.widget_harness')
        local default_nil = widget_harness.default_nil()
        options = {
            globals={DEFAULT_NIL=default_nil},
            require_modules={
                ['gui.widgets']=widget_harness.widgets(nil, default_nil),
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/widgets/asset_button.lua' then
        local widget_harness = require('support.widget_harness')
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        widgets.Widget.ATTRS{
            visible=true,
            enabled=true,
            disabled=false,
            tooltip=default_nil,
        }
        widgets.Label.makeButtonLabelText = function(spec)
            return spec.chars
        end
        options = {
            globals={
                DEFAULT_NIL=default_nil,
                defclass=widget_harness.defclass,
            },
            require_modules={
                utils={getval=function(value)
                    if type(value) == 'function' then return value() end
                    return value
                end},
                ['gui.widgets']=widgets,
            },
            reqscript={
                ['dwarfui/widget_extensions']={},
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/widgets/hover_action_rail.lua' then
        local widget_harness = require('support.widget_harness')
        local default_nil = widget_harness.default_nil()
        options = {
            globals={
                DEFAULT_NIL=default_nil,
                defclass=widget_harness.defclass,
            },
            require_modules={
                gui={paint_frame=function() end},
                ['gui.widgets']=widget_harness.widgets(nil, default_nil),
            },
            reqscript={
                ['dwarfui/class']={
                    is_instance_of=function() return false end,
                },
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/pointer_poller.lua' then
        options = {
            globals={
                dfhack={
                    dwarfui={},
                    screen={getMousePos=function() return nil, nil end},
                    timeout=function() end,
                },
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/tooltip_root_resolver.lua' then
        local widget_harness = require('support.widget_harness')
        local widgets = widget_harness.widgets()
        ---@class tests.PackageContractRootResolverOverlay
        local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
        options = {
            globals={
                dfhack={
                    gui={
                        getDFViewscreen=function() return nil end,
                        getCurViewscreen=function() return nil end,
                        matchFocusString=function() return false end,
                    },
                },
            },
            require_modules={
                ['plugins.overlay']={
                    OverlayWidget=OverlayWidget,
                    get_state=function() return {db={}} end,
                    isOverlayEnabled=function() return false end,
                    normalize_list=function(value) return {value} end,
                    simplify_viewscreen_name=function(value) return value end,
                },
            },
            reqscript={
                ['dwarfui/class']={
                    is_instance_of=function() return false end,
                },
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/tooltip_target.lua' then
        options = {}
    elseif package_path ==
            'scripts_modinstalled/dwarfui/tooltip_target_detector.lua' then
        options = {
            reqscript={
                ['dwarfui/pointer']={
                    PointerDispatcher={resolve=function()
                        return {kind='miss'}
                    end},
                },
                ['dwarfui/tooltip_root_resolver']={
                    TooltipRootResolver={
                        new=function()
                            return {resolve=function() return nil end}
                        end,
                    },
                },
                ['dwarfui/tooltip_target']=tooltip_target_stub(),
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/tooltip_map_target.lua' then
        options = {
            globals={dfhack={dwarfui={}}},
            reqscript={
                ['dwarfui/tooltip_root_resolver']={
                    TooltipRootResolver={
                        new=function()
                            return {resolve=function() return nil end}
                        end,
                    },
                },
                ['dwarfui/tooltip_target']=tooltip_target_stub(),
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/tooltip_service.lua' then
        options = {
            globals={dfhack={dwarfui={}}},
            reqscript={
                ['dwarfui/tooltip_target']=tooltip_target_stub(),
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/tooltip_render_hook.lua' then
        options = {
            globals={dfhack={dwarfui={}}},
            require_modules={
                ['plugins.overlay']={
                    render_viewscreen_widgets=function() end,
                },
            },
        }
    elseif package_path == 'scripts_modinstalled/dwarfui/tooltip.lua' then
        local widget_harness = require('support.widget_harness')
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        options = {
            globals={
                COLOR_BLACK='black',
                COLOR_WHITE='white',
                DEFAULT_NIL=default_nil,
                defclass=widget_harness.defclass,
                dfhack={
                    pen={parse=function(value) return value end},
                    gui={
                        getDFViewscreen=function() return nil end,
                        getCurViewscreen=function() return nil end,
                    },
                    screen={
                        getWindowSize=function() return 80, 25 end,
                        invalidate=function() end,
                    },
                },
            },
            require_modules={
                gui={
                    Screen={},
                    FRAME_INTERIOR='interior',
                    Painter={new=function()
                        return widget_harness.rect(0, 0, 80, 25)
                    end},
                    paint_frame=function() end,
                },
                ['gui.widgets']=widgets,
                ['plugins.overlay']={OverlayWidget={}},
            },
            reqscript={
                ['dwarfui/class']={
                    is_instance_of=function() return false end,
                },
                ['dwarfui/widget_extensions']={},
                ['dwarfui/text']={wrap_text=function() return {''} end},
                ['dwarfui/tooltip_service']={
                    service={
                        get_intent=function() return nil end,
                        get_diagnostics=function() return {revision=0} end,
                        set_intent_observer=function() end,
                    },
                },
                ['dwarfui/tooltip_render_hook']={
                    TooltipRenderTransport={OVERLAY=1, SCREEN=2},
                    manager={
                        get_diagnostics=function()
                            return {generation=1}
                        end,
                        set_presenter=function() end,
                        set_current_intent_revision=function() end,
                        ensure_overlay=function() end,
                        clear_selection=function() end,
                    },
                },
                ['dwarfui/tooltip_registration']={
                    register=function() return true end,
                    unregister=function() return true end,
                },
            },
        }
    elseif package_path == 'scripts_modinstalled/dwarfui/popover.lua' then
        local widget_harness = require('support.widget_harness')
        local default_nil = widget_harness.default_nil()
        options = {
            globals={defclass=widget_harness.defclass},
            require_modules={
                gui={WINDOW_FRAME='window'},
                ['gui.widgets']=widget_harness.widgets(nil, default_nil),
            },
        }
    elseif package_path == 'scripts_modinstalled/dwarfui/mood_popover.lua' then
        options = {
            globals={
                defclass=function(class)
                    class = class or {}
                    return setmetatable(class, {__call=function(class_table)
                        return setmetatable({}, {__index=class_table})
                    end})
                end,
                COLOR_LIGHTGREEN='lightgreen', COLOR_GREEN='green',
                COLOR_LIGHTCYAN='lightcyan', COLOR_WHITE='white',
                COLOR_YELLOW='yellow', COLOR_LIGHTRED='lightred',
                COLOR_RED='red',
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/minecart_route.lua' then
        options = {
            globals={
                defclass=function(class)
                    class = class or {}
                    class.ATTRS = function() end
                    return setmetatable(class, {__call=function(class_table,
                            attributes)
                        local instance = attributes or {}
                        setmetatable(instance, {__index=class_table})
                        if instance.init then instance:init() end
                        return instance
                    end})
                end,
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/tooltip_registration.lua' then
        options = {
            globals={
                dfhack={
                    screen={getMousePos=function() return nil, nil end},
                    timeout=function() end,
                },
            },
            require_modules={},
            reqscript={
                ['dwarfui/pointer_poller']={
                    PointerPoller={
                        new=function()
                            return {
                                start=function() return false end,
                                stop=function() return false end,
                                get_diagnostics=function()
                                    return {
                                        module_generation=1,
                                        generation=0,
                                        running=false,
                                        scheduled=false,
                                        current=true,
                                        sample_sequence=0,
                                    }
                                end,
                            }
                        end,
                    },
                },
                ['dwarfui/tooltip_service']={
                    service={
                        get_registrations=function()
                            return setmetatable({}, {__mode='k'})
                        end,
                        registration_count=function() return 0 end,
                        register=function() return true end,
                        unregister=function() return false end,
                        release_target=function() return false end,
                        shutdown=function() end,
                        set_intent_observer=function() end,
                        accept_pointer_observation=function() end,
                        get_diagnostics=function()
                            return {
                                api_version=1,
                                generation=1,
                                registration_count=0,
                                revision=0,
                                last_sequence=0,
                            }
                        end,
                    },
                },
                ['dwarfui/tooltip_target_detector']={
                    TooltipTargetDetector={
                        new=function()
                            return {detect=function()
                                return {kind='miss'}
                            end}
                        end,
                    },
                },
                ['dwarfui/tooltip_map_target']={
                    registry={
                        registration_count=function() return 0 end,
                        get_owner_roots=function() return {} end,
                        register=function() return {} end,
                        update=function() return false end,
                        unregister=function() return false end,
                        get_diagnostics=function()
                            return {
                                generation=1,
                                coordinate_bucket_count=0,
                            }
                        end,
                    },
                },
                ['dwarfui/tooltip_target']=tooltip_target_stub(),
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/unit_card_task.lua' then
        options = {
            globals={
                df={
                    job_type={
                        BringItemToDepot=1,
                        BringItemToShop=2,
                        StoreItemInStockpile=3,
                        StoreItemInBag=4,
                        StoreItemInLocation=5,
                        StoreItemInBarrel=6,
                        StoreItemInBin=7,
                        StoreItemInVehicle=8,
                        DumpItem=9,
                    },
                    job_role_type={Hauled=1, QueuedContainer=2},
                },
            },
        }
    end
    return module_loader.load(repo_root, 'src/' .. package_path, options)
end

describe('DwarfUI package contract', function()
    it('publishes the expected metadata', function()
        local info = read_source('info.txt')
        local expected = {
            ID='dwarfui',
            NAME='DwarfUI',
            NUMERIC_VERSION='1',
            DISPLAYED_VERSION='0.1.0',
            DESCRIPTION='Reusable DFHack UI infrastructure and user-facing interface enhancements.',
        }
        for key, value in pairs(expected) do
            contains(info, ('[%s:%s]'):format(key, value))
        end
    end)

    it('supports Lua 5.3 and newer without an artificial upper bound',
            function()
        local rockspec = read_repository_file('dwarfui.rockspec')
        contains(rockspec, '"lua >= 5.3"')
        assert.is_nil(rockspec:find('< 5.4', 1, true))
    end)

    it('ships expected Lua module contracts', function()
        for _, relative_path in ipairs(shipped_modules) do
            local package_path = 'scripts_modinstalled/' .. relative_path
            local source = read_source(package_path)
            contains(source, '--@ module=true')
            assert.is_nil(source:lower():find('soulsearch', 1, true))

            local _, module_result = load_public_module(package_path)
            assert.equals('table', type(module_result), package_path)
        end
    end)

    it('ships the process-wide tooltip service object', function()
        local _, module = load_public_module(
            'scripts_modinstalled/dwarfui/tooltip_service.lua')

        assert.equals('table', type(module.TooltipService))
        assert.equals('table', type(module.service))
        assert.is_equal(module.TooltipService, getmetatable(module.service))
        assert.equals('function',
            type(module.service.accept_pointer_observation))
    end)

    it('ships numeric tooltip target and observation enums', function()
        local _, module = load_public_module(
            'scripts_modinstalled/dwarfui/tooltip_target.lua')

        assert.equals('number',
            type(module.TooltipTargetKind.WIDGET))
        assert.equals('number',
            type(module.TooltipTargetKind.MAP_TILE))
        assert.equals('number',
            type(module.TooltipPointerObservationKind.TARGET))
        assert.equals('number',
            type(module.TooltipPointerObservationKind.BLOCKED))
        assert.equals('number',
            type(module.TooltipPointerObservationKind.MISS))
    end)

    it('ships the process-wide tooltip render-hook manager', function()
        local _, module = load_public_module(
            'scripts_modinstalled/dwarfui/tooltip_render_hook.lua')

        assert.equals('table', type(module.TooltipRenderHookManager))
        assert.equals('table', type(module.TooltipRenderTransport))
        assert.equals('number', type(module.TooltipRenderTransport.OVERLAY))
        assert.equals('number', type(module.TooltipRenderTransport.SCREEN))
        assert.is_not_equal(module.TooltipRenderTransport.OVERLAY,
            module.TooltipRenderTransport.SCREEN)
        assert.equals('table', type(module.manager))
        assert.is_equal(
            module.TooltipRenderHookManager, getmetatable(module.manager))
        assert.equals('function', type(module.manager.ensure_overlay))
        assert.equals('function', type(module.manager.ensure_screen))
    end)

    it('ships the process-wide intent-driven tooltip presenter', function()
        local _, module = load_public_module(
            'scripts_modinstalled/dwarfui/tooltip.lua')

        assert.equals('table', type(module.TooltipPresenter))
        assert.equals('table', type(module.presenter))
        assert.is_equal(module.TooltipPresenter,
            getmetatable(module.presenter))
        assert.equals('function', type(module.presenter.present))
        assert.equals('function', type(module.presenter.get_diagnostics))
        assert.is_nil(module.TooltipAgent)
    end)

    it('ships the exact map-tile public registration contract ' ..
            '#map_tile_contract', function()
        local _, module = load_public_module(
            'scripts_modinstalled/dwarfui/tooltip.lua')

        assert.equals('function', type(module.register_map_tile))
        assert.equals('function', type(module.update_map_tile))
        assert.equals('function', type(module.unregister_map_tile))
    end)

    it('keeps tooltip input and registration free of UI hosts', function()
        local registration = read_source(
            'scripts_modinstalled/dwarfui/tooltip_registration.lua')
        local service = read_source(
            'scripts_modinstalled/dwarfui/tooltip_service.lua')
        local map_target = read_source(
            'scripts_modinstalled/dwarfui/tooltip_map_target.lua')
        local root_resolver = read_source(
            'scripts_modinstalled/dwarfui/tooltip_root_resolver.lua')
        for _, source in ipairs({
                registration, service, map_target, root_resolver,
                read_source(
                    'scripts_modinstalled/dwarfui/tooltip_target.lua')}) do
            for _, forbidden in ipairs({
                    "require('gui')",
                    "require('gui.widgets')",
                    'gui.ZScreen',
                    'OverlayWidget{',
                    'TooltipRenderer',
                    'TooltipPresenter',
                }) do
                assert.is_nil(source:find(forbidden, 1, true), forbidden)
            end
        end
        for _, forbidden in ipairs({
                'show(',
                'raise(',
                'dismiss(',
                'sendInputToParent',
                'onInput',
                'onIdle',
            }) do
            assert.is_nil(registration:find(forbidden, 1, true), forbidden)
        end
    end)

    it('does not construct a tooltip screen or overlay widget', function()
        for _, relative_path in ipairs({
                'scripts_modinstalled/dwarfui/tooltip.lua',
                'scripts_modinstalled/dwarfui/tooltip_registration.lua',
                'scripts_modinstalled/dwarfui/tooltip_service.lua',
                'scripts_modinstalled/dwarfui/tooltip_root_resolver.lua',
                'scripts_modinstalled/dwarfui/tooltip_target.lua',
                'scripts_modinstalled/dwarfui/tooltip_target_detector.lua',
                'scripts_modinstalled/dwarfui/tooltip_map_target.lua',
                'scripts_modinstalled/dwarfui/tooltip_render_hook.lua',
            }) do
            local source = read_source(relative_path)
            assert.is_nil(source:find('gui.ZScreen{', 1, true), relative_path)
            assert.is_nil(source:find(
                'overlay.OverlayWidget{', 1, true), relative_path)
            assert.is_nil(source:find(
                'TooltipServiceScreen', 1, true), relative_path)
        end
    end)

    it('keeps tooltip input layers independent of presentation modules',
            function()
        for _, relative_path in ipairs({
                'scripts_modinstalled/dwarfui/pointer.lua',
                'scripts_modinstalled/dwarfui/pointer_poller.lua',
                'scripts_modinstalled/dwarfui/tooltip_root_resolver.lua',
                'scripts_modinstalled/dwarfui/tooltip_target.lua',
                'scripts_modinstalled/dwarfui/tooltip_target_detector.lua',
                'scripts_modinstalled/dwarfui/tooltip_map_target.lua',
                'scripts_modinstalled/dwarfui/tooltip_service.lua',
                'scripts_modinstalled/dwarfui/tooltip_registration.lua',
            }) do
            local source = read_source(relative_path)
            assert.is_nil(source:find(
                "reqscript('dwarfui/tooltip')", 1, true), relative_path)
            assert.is_nil(source:find(
                "reqscript('dwarfui/tooltip_render_hook')", 1, true),
                relative_path)
            assert.is_nil(source:find(
                'TooltipPresenter', 1, true), relative_path)
        end
    end)

    it('keeps exact map-target detection generic and host-independent',
            function()
        local source = read_source(
            'scripts_modinstalled/dwarfui/tooltip_map_target.lua')
        for _, forbidden in ipairs({
                'minecart',
                'Minecart',
                'TooltipRenderer',
                'TooltipPresenter',
                'gui.ZScreen',
                'onInput',
                'tileToScreen',
                'renderMapOverlay',
            }) do
            assert.is_nil(source:find(forbidden, 1, true), forbidden)
        end
    end)

    it('does not compensate for wrapper-shaped class test doubles',
            function()
        for _, relative_path in ipairs({
                'scripts_modinstalled/dwarfui/tooltip.lua',
                'scripts_modinstalled/dwarfui/tooltip_root_resolver.lua',
                'scripts_modinstalled/dwarfui/widgets/hover_action_rail.lua',
            }) do
            local source = read_source(relative_path)
            assert.is_nil(source:find(
                'get_instance_class', 1, true), relative_path)
            assert.is_nil(source:find(
                "rawget(class, '__index')", 1, true), relative_path)
        end
    end)

    it('roots shipped modules in the package', function()
        for _, relative_path in ipairs(shipped_modules) do
            local file = assert(io.open(source_path(
                'scripts_modinstalled/' .. relative_path), 'rb'))
            file:close()
        end
    end)

    it('ships the reusable asset-button class contract', function()
        local source = read_source(
            'scripts_modinstalled/dwarfui/widgets/asset_button.lua')
        contains(source, 'AssetButton = defclass')
        local _, module = load_public_module(
            'scripts_modinstalled/dwarfui/widgets/asset_button.lua')
        assert.equals('table', type(module.AssetButton))
    end)

    it('ships the reusable hover-action rail class contracts', function()
        local package_path =
            'scripts_modinstalled/dwarfui/widgets/hover_action_rail.lua'
        local source = read_source(package_path)
        for _, class_name in ipairs({
                'HoverActionTarget',
                'HoverAction',
                'HoverActionRail',
            }) do
            contains(source, class_name .. ' = defclass')
        end
        local _, module = load_public_module(package_path)
        assert.equals('table', type(module.HoverActionTarget))
        assert.equals('table', type(module.HoverAction))
        assert.equals('table', type(module.HoverActionRail))
    end)

    it('includes the complete mood-popover payload and registration', function()
        local registration = read_source(mood_popover_payload.registration)
        contains(registration, '--@ module=true')
        contains(registration, 'OVERLAY_WIDGETS')
        contains(registration, 'mood_popover=MoodPopoverOverlay')

        local model = read_source(mood_popover_payload.model)
        contains(model, '--@ module=true')
        contains(model, 'MoodPopoverModel = defclass')

        local widget = read_source(mood_popover_payload.widget)
        contains(widget, '--@ module=true')
        contains(widget, 'Popover = defclass')
    end)

    it('includes the complete minecart-route marker payload and registration',
            function()
        local registration = read_source(minecart_route_payload.registration)
        contains(registration, '--@ module=true')
        contains(registration, 'OVERLAY_WIDGETS')
        contains(registration,
            'minecart_route_markers=MinecartRouteMarkersOverlay')

        local model = read_source(minecart_route_payload.model)
        contains(model, 'MinecartRouteMarkerProjection = defclass')
    end)

    it('ships the dwarfui reload command', function()
        local command = read_source('scripts_modinstalled/dwarfui.lua')
        contains(command, 'dwarfui reload')
        contains(command, "qerror('Usage: dwarfui [reload]')")
        contains(command, "require('plugins.overlay').rescan()")
    end)
end)
