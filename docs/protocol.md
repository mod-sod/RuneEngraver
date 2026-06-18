# RUNE addon-message protocol

The contract between this addon and the server-side `mod-rune-engraving` engine.
It's intentionally tiny and mirrors the style of CleanBot's `MBOT` protocol:
addon messages, `~`-separated fields, a `BEGIN…END` sequence so every line stays
well under the 254-char addon-message cap. The same grammar is documented on the
server side (the engine repo's `docs/addon-ui.md`) — keep both in sync.

## Transport

All messages are **addon messages** with prefix `RUNE`, sent as a **self-whisper**:

```lua
SendAddonMessage("RUNE", body, "WHISPER", UnitName("player"))
```

The server receives them through `PlayerScript::OnPlayerBeforeSendChatMessage`
(no framework, no core edits) and replies with addon whispers the addon renders.
The self-whisper works even solo because the server's chat hook fires regardless
of delivery. `Addon.Channel` must be enabled server-side (default on).

## Client → server

| Body | Meaning |
|---|---|
| `REQ` | Send me the full panel state. |
| `ENG~<slot>~<runeId>` | Engrave `runeId` into `slot`. |
| `DEL~<slot>` | Clear `slot`. |

`<slot>` is the numeric `RuneSlot` index (Head 0 … Ring 10).

## Server → client

One push is a `BEGIN`, then a `SLOT` line per slot (each followed by a `RUNE`
line per engravable rune), an optional `MSG`, then `END`. The client accumulates
between `BEGIN` and `END`, then renders.

| Body | Fields | Meaning |
|---|---|---|
| `BEGIN~<prereqMet>~<level>` | `prereqMet` = 0/1 (learned Engraving), `level` = character level | start a state push |
| `SLOT~<slot>~<name>~<minLevel>~<current>` | `name` e.g. "Chest"; `minLevel` to unlock; `current` = engraved rune id (0 = none) | one per slot |
| `RUNE~<slot>~<runeId>~<icon>~<locked>~<spellId>~<name>` | `icon` = inventory-icon name (→ `Interface\Icons\<icon>`); `locked` = 0/1 (1 = gated rune not yet discovered, greyed in the panel); `spellId` = the spell the rune teaches (the panel shows its tooltip via `spell:<spellId>`, 0 = none); `name` is **last** so it may contain `~` | one per class/slot-legal rune (locked + unlocked) |
| `MSG~<text>` | feedback (engrave result / failure reason) | optional, inside the block |
| `END` | — | push complete → render |

After an `ENG`/`DEL`, the server re-sends the whole `BEGIN…END` block with a
`MSG`, so the client just re-renders from the fresh model.

## Parsing

`Comms.lua` keeps the parse pure (`RE_NewState` / `RE_HandleLine`) so it's unit-
tested in `spec/comms_spec.lua` without a live client. `RUNE` lines are parsed by
splitting off the first four fields (slot, runeId, icon, locked) and keeping the
remainder as the name (so a name containing `~` survives); other lines split on
every `~`.
