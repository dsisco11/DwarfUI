# Overview

This is a DFHack Lua plugin project (Wiki: <https://docs.dfhack.org/en/stable/docs/dev/Lua%20API.html>).
All built/test tasks are to be run using the scripts in the `./tools/` directory.

## LUA Code Rules

- Start production modules with `--@ module=true` and export through the
  DFHack module environment; do not use `local M = {}; return M`.
- Load project modules with `reqscript('path/without/extension')`. Use
  `require()` only for DFHack or external libraries; never add fallback loaders.
- Add reload-managed modules to `dwarfui/module_registry.lua` in dependency
  order and update registry/package tests.
- Use immutable numeric `---@enum` tables for every closed discriminator set;
  never use loose strings or magic numbers:

  ```lua
  ---@enum dwarfui.TooltipTargetKind
  TooltipTargetKind = {
      WIDGET=1,
      MAP_TILE=2,
  }
  ```

- Annotate enum-typed fields, parameters, and returns; always assign and compare
  named enum members. Convert internal sentinels at module boundaries.
- Add LuaDoc/Doxygen-style comments for every class and method.
