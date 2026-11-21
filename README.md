# RandomGame1

A Roblox place built code-first with [Rojo](https://rojo.space). All code lives in files and reaches Studio through Rojo; nothing is typed into Studio.

## Setup

Tools are pinned in `rokit.toml` (Rojo, Wally, wally-package-types, Selene, StyLua, Lune, luau-lsp).

```
rokit install
wally install
rojo sourcemap default.project.json -o sourcemap.json
wally-package-types -s sourcemap.json Packages/
```

Packages (from `wally.toml`):

| Package | Version | Mounted at |
| --- | --- | --- |
| React | `jsdotlua/react@17.2.1` | `ReplicatedStorage.Packages.React` |
| ReactRoblox | `jsdotlua/react-roblox@17.2.1` | `ReplicatedStorage.Packages.ReactRoblox` |

## Checks

```
lune run scripts/check
```

Every check must pass before Studio sees anything:

1. `rojo build`: the project and files are valid
2. Lune unit tests (`tests/*.spec.luau`, run by `tests/run.luau`)
3. Selene: lint (warnings count as failures)
4. StyLua: formatting (run `stylua src tests scripts` to fix)
5. Luau type check against the Roblox API (via luau-lsp)

## Layout

| Path | Mounted at | What |
| --- | --- | --- |
| `src/shared/` | `ReplicatedStorage.Shared` | Code used by both server and client |
| `src/server/` | `ServerScriptService.Server` | Server code (`Main.server.luau` is the entry point) |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | Client code (`Main.client.luau` mounts the React UI) |
| `Packages/` | `ReplicatedStorage.Packages` | Wally packages (generated, gitignored) |
| `tests/` | | Lune specs for pure modules in `src/shared` |
| `scripts/check.luau` | | Runs every check |
| `TRAPS.md` | | Rules learned from things that broke |

## Running in Studio

```
rojo build default.project.json -o RandomGame1.rbxl
rojo serve
```

Open `RandomGame1.rbxl` in Studio, open the Rojo plugin and click **Connect**. Edits to files now sync live. Restart `rojo serve` after adding a new `$path` to `default.project.json`.
