# DwarfUI

DwarfUI is a DFHack mod that provides reusable UI infrastructure and its own
user-facing interface enhancements.

The shared public Lua namespace is installed under `scripts_modinstalled/dwarfui/`.
The tooltip port reserves these downstream module paths:

- `dwarfui/text`
- `dwarfui/widget_extensions`
- `dwarfui/pointer`
- `dwarfui/tooltip`

All modules expose stable return-table contracts. `dwarfui/text` provides
standalone text wrapping, and importing `dwarfui/widget_extensions` installs
the declarative tooltip and pointer attributes on DFHack's native widget
classes. `dwarfui/pointer` and `dwarfui/tooltip` remain reserved placeholders
until their later porting phases.
