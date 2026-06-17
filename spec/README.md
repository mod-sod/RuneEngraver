# Specs

Offline unit tests for the addon's **pure logic** (the `RUNE` protocol parser and
the outbound senders) under a bare Lua 5.1 / LuaJIT interpreter against a minimal
WoW-API mock — no live client.

Run from the addon root:

```
luajit spec\run.lua
```

A pass prints `N passed, 0 failed` and exits 0. `framework.lua` is a tiny
busted-style harness (`describe`/`it`/`assert.*`); `wow_mock.lua` stubs just
enough API for the file under test to load; register new spec files in `run.lua`.
CI runs the same via `.github/workflows/test.yml`.

UI/frame behavior (`Panel.lua`) is out of scope here — it's verified in-game.
Keep pure logic in side-effect-free helpers so specs can exercise it directly.
