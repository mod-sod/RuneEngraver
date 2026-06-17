# RuneEngraver

A World of Warcraft **3.3.5a** (WotLK) addon that lets you engrave runes from an
in-game panel, opened by a button on the **Character Sheet**. It's the client UI
for the server-side [`mod-rune-engraving`](https://github.com/) engine — the two
talk over a small addon-message protocol and otherwise know nothing about each
other.

The server-side gossip **Rune Engraver** NPC still works without this addon; the
panel is just a nicer front-end onto the same engine.

## Requirements

- A server running the **`mod-rune-engraving`** module (plus content that adds
  runes, e.g. `mod-sod-mage`).
- The server's `Addon.Channel` world config enabled (on by default).
- No client patch — this is a pure Lua addon.

## Install

Drop the `RuneEngraver` folder into `World of Warcraft/Interface/AddOns/` so you
have `Interface/AddOns/RuneEngraver/RuneEngraver.toc`, then restart the client.

## Use

- Open your **Character Sheet** (default `C`) and click the rune button at the
  top-right (just left of the close button), or type `/rune`.
- Pick a slot on the left, then click a rune on the right to engrave it. Locked
  slots show `(unlocks at N)`; the engraved rune is highlighted; **Remove rune**
  clears the slot.

## How it works

The addon and the engine couple only through the **`RUNE` addon-message
protocol** (self-whisper, `LANG_ADDON`): the panel asks for state and sends
engrave/remove actions; the server replies with the slot/rune model to render.
The grammar is in [docs/protocol.md](docs/protocol.md) — the client half of a
contract documented on both sides (the engine repo has the server half).

## Development

- **Tests** (pure protocol logic, no client): `luajit spec\run.lua` →
  `N passed, 0 failed`. The harness is a dependency-free busted-style runner;
  CI runs the same on every `.lua` change.
- **Lint**: `lua-language-server --check` should come back clean.

## License

MIT — see [LICENSE](LICENSE).
