# Wick's Beasts and Things - Changelog

## Unreleased

- Beast atlas. Reads your pet's spell book whenever one is out and files
  what it found under that pet's family, then names a family's abilities
  in the tooltip of any beast of that family. /wbt beasts to list.
- A Beasts tab in the kit window showing the whole roster, what sets
  each family apart, and what they all carry.

## 0.1.0 - 2026-09-17 (Forever, beta)

### First cut of the hunter kit on WickCore

- Requires WickCore. Interface 16001.
- Pet card: name, family, level, happiness with damage bonus and loyalty
  direction, loyalty rank, free training points, diet. Reads through
  C_PetInfo and goes quiet where values turn secret in combat.
- Feed key: a secure button whose macro is rewritten out of combat to cast
  Feed Pet and use the best food in bags the pet will eat, with the level
  rule applied. Pin a food with /wbt food, prefer the cheapest in Options.
- Ammo watch: equipped and reserve counts, wrong-ammo detection against the
  ranged weapon, red below a configurable threshold.
- Talents: export, import, save, apply, through Blizzard's own parser.
- Pre-pull checklist: aspect, pet out, pet fed, ammo stocked, Trueshot Aura.
- Racials row. Kit panel at /wbt kit. Minimap launcher and a page under
  Options, Wick's Mods.
