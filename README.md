# DwarfUI

DwarfUI is a DFHack mod that provides reusable UI infrastructure and its own
user-facing interface enhancements.

The shared public Lua namespace is installed under `scripts_modinstalled/dwarfui/`.
The tooltip port reserves these downstream module paths:

- `dwarfui/text`
- `dwarfui/widget_extensions`
- `dwarfui/pointer`
- `dwarfui/tooltip`

The modules currently expose stable return-table contracts. Their functionality
is implemented incrementally by the phases in
`Docs/tooltip-system-port.todo`; placeholder modules do not claim behavior that
has not yet been ported.
