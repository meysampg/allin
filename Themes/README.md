# Themes

Each `*.allintheme` folder is a theme pack: a `theme.json` manifest plus optional asset files
(images, sounds, fonts, effect definitions) and a `LICENSE.txt`.

- `theme.json` holds `schemaVersion`, `id`, `name`, `version`, `author`, `license`, an optional
  `extends` (another pack id), a `palette` of 16 named `#RRGGBB` colors, and `slots`.
- A slot entry (for example `card.face`, `chip.25`, `sound.win`) names exactly one source:
  `procedural` (a built-in generator id, with optional `params`), `file`, or `files`.
- Slots a pack leaves out fall back through its `extends` chain, then `hearthwood`, then the
  code-drawn defaults, so a pack can override only what it wants to change.
- `hearthwood.allintheme` is the shipped base pack. It uses only procedural sources.

Check packs with `allin-tool theme validate [path...]` (default: this folder). The format, slot
list and validation rules are specified in `docs/PLAN.md` section 2.
