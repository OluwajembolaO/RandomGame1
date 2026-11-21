# TRAPS

Rules learned the hard way. Each one says what broke, the rule, and why. Add one every time something breaks and gets fixed.

## Toolchain

1. **Run tools through Rokit's shims, not whatever `rojo` is first on PATH.**
   A standalone `C:\rojo-7.7.0-windows-x86_64` sits earlier on PATH than `~/.rokit/bin`, so a bare `rojo` ran 7.7.0 instead of the pinned 7.7.1. `scripts/check.luau` calls `~/.rokit/bin/<tool>` first. Remove the old folder from PATH, or Studio's Rojo plugin and the CLI can drift apart.

2. **New Rokit tools must be trusted before `rokit add` works.**
   `rokit add` refused with "has not been marked as trusted". Run `rokit trust <owner/repo>` first, and only for repos you mean to run.

3. **Format before checking.** The StyLua check fails on any formatting difference. Run `stylua src tests scripts` and then `lune run scripts/check`.

4. **Selene warnings count as failures.** Selene exits 0 when it only finds warnings, so the check script reads its summary and fails on any warning.

## Rojo and sourcemaps

5. **Regenerate `sourcemap.json` after `wally install` or any change to `default.project.json`.**
   A stale sourcemap made `wally-package-types` fail with "Linker node not found in sourcemap", and made Luau LSP report "Unknown require". Run `rojo sourcemap default.project.json -o sourcemap.json`, then `wally-package-types -s sourcemap.json Packages/`.

6. **Restart `rojo serve` after adding a new `$path` mount**, then reconnect the Studio plugin. Otherwise the new folder silently never reaches Studio.

7. **Selene needs `std = "roblox"`.** Without it, Selene can't parse Luau type syntax (`type X = ...` gave "unexpected token").

## Roblox API

8. **Parent ScreenGuis to `PlayerGui`, not to the `Player`.** A ScreenGui under the Player object never renders, and there's no error.

9. **Text color is `TextColor3`, and a ModuleScript must `return` its value.** Both failed silently.

10. **`game.JobId` is `""` in Studio.** Use a GUID for a DataStore session lock id, or every Studio session looks like the same server.

11. **Players spawn facing the SpawnLocation's -Z.** Place whatever they should see first on the spawn's -Z side.

12. **`Lighting.Technology` can't be set from a script.** Set it in `default.project.json`.

13. **Scripts can't set `MeshPart.MeshId`.** Load meshes at runtime with `AssetService:CreateMeshPartAsync(Content.fromUri(id))`, with a part-built fallback until they load.

14. **Only a few sounds ship with Roblox.** Studio's `content/sounds` has jump, land, footsteps, splash and a slider tick. Anything else needs uploaded `rbxassetid://` audio.

## World look

15. **Size BillboardGuis in studs (`UDim2.fromScale`), not pixels.** Pixel-sized signs stay the same size up close and cover the HUD. In studs they shrink with distance like real signs.

16. **Big Neon surfaces flood the screen.** Keep Neon for thin accents and use SmoothPlastic, plus particles, for large surfaces.

17. **Roblox draws at most 31 Highlights at once**, and the extra ones silently don't render. Group things into Models and outline each group once.

18. **One Highlight only outlines its adornee's silhouette.** A part inside the same Model as the ground gets no edge, so split models you want edged separately.

## Types

19. **String-literal unions widen to `string` across module boundaries** (old Luau type solver). Functions that take such a value from another module accept `string`, and the literal type is documented in a comment.

20. **Selene wants a message on every `assert`.** `assert(x)` is an error under `std = "roblox"`.

21. **Strict mode rejects config lists whose items have different fields.** Leave those config files non-strict, type their entries as `any` where they're loaded, and have each consumer declare the fields it reads.

22. **Annotate find-or-nil helpers (`: any?`).** Otherwise Luau infers the return type from the first `return` and rejects the `return nil`.

## UI (React)

23. **Hidden panels must not keep their contents mounted.** If panels stay in the tree and only `Visible` changes, their contents (ViewportFrames, ticking clocks) keep running while closed. Drop the contents shortly after closing.

24. **ViewportFrames aren't reliably drawn inside CanvasGroups.** Don't wrap 3D previews in a CanvasGroup fade.

## Studio MCP

25. **"Enable Studio as MCP server" must be on, with a place open.** Until then the MCP bridge connects but lists zero tools. After Studio restarts or opens a place in a new window, check the toggle again.

26. **Don't sync into whatever place happens to be open.** Playtest a fresh `rojo build -o RandomGame1.rbxl` and use `rojo serve` with that same place.

27. **Studio's character_navigation can't path onto floating parts** ("Can not find a route"). Walk to the ground beside them and send jump and move keys. A failed MCP tool call can also end the playtest, so check `get_studio_state` before the next step.

28. **`execute_luau` may wait for approval in Studio** and return nothing during play. Use `inspect_instance`, `search_game_tree` and `screen_capture` for read-only checks.

29. **Studio's generation tools publish assets to your account and insert into the open place.** To stay code-first, copy the asset ids into config, have the code rebuild them, and delete the generated instances from the place.

30. **Studio's MCP has no 2D image generation.** `upload_image` only uploads images you already have.

38. **`screen_capture` needs Studio's window in front during play.** With Studio behind VS Code, playtest captures came back half-drawn (a stale frame over the sky) or solid black, HUD included, while the game itself was fine. Check state with `execute_luau` (Client) first, and ask for Studio to be brought forward before judging visuals.

39. **The Studio importer drops plain material colors, and GLB arrives rotated 180°.** The Blender cart arrived default grey with its front at +Z. Set colors and materials in Studio, and turn the model around its pivot. Keep "Set Pivot to Scene Origin" ticked so the pivot is the Blender origin. Roblox materials still showed texture detail on the MeshParts.

41. **Never rewrite a light's `Enabled` when it hasn't changed.** The client's distance culling set `Enabled` on all ~750 kit lights every 0.4 s, even to the same value, and the whole cave rendered black (crystals glowed, nothing was lit). With the loop stopped, 1, 12, 32 and 64 lights all lit the station normally, and so did per-frame `Brightness` changes for flicker and pulse. Compare before writing.

42. **Server-made lights on Attachments don't light anything on the client until the client writes a property.** Every kit light rendered as nothing on a fresh playtest (the cave was black, Neon still glowed) even though the client had them enabled, in range and correctly placed. Toggling `Enabled` off and on once from the client lit everything at once, and no other change (lighting values, light count, an extra light) did. Doing that toggle automatically 0.4 s after the lights arrived was too early and didn't help. Client-made lights that started enabled were black too, so it isn't about replication. What matters is that the light's first change happens with the camera nearby: lights created and enabled during the cave build, before the character spawned there, never lit. The fix: clients make every cave and cart light (`client/CaveLights` from `RunInfo.CaveSeed`, and `client/CartFx`), each starting `Enabled = false`. `Fx` distance culling switches each one on when the camera comes within range.

40. **`rojo syncback` asks for confirmation and writes default-value noise.** Use `-y`, and list noisy properties (`ExplorerIconContent`, `SerializedOverrides`) under `syncbackRules.ignoreProperties` in `content.project.json`. While `rojo serve` is connected, the synced `.rbxm` also appears in Studio next to the original, so delete the duplicate.

## Blender MCP

37. **Use one Blender MCP add-on only.** The official Blender Lab extension (`lab_blender_org/mcp`, paired with Claude Desktop's Blender extension) and the third-party `mcp-for-blender` add-on both listen on port 9876. Whichever binds first wins, and the other server connects to the wrong add-on and hangs on its first command (`get_addon_info`), so Claude Code reports a 30s connect timeout. This project uses the official one: `.mcp.json` runs Claude Desktop's `blender-mcp.exe` from its extension venv. If Claude Desktop updates that extension and the path changes, update `.mcp.json`.

## Git

31. **Pin LF line endings in `.gitattributes`.** With `core.autocrlf` on Windows, Git would check files out as CRLF, and `stylua --check` (`line_endings = "Unix"`) would fail on every fresh clone.

## Numbers and checks

32. **Keep integer math under 2^53.** Use MINSTD (`seed * 48271 % 2147483647`) for seeded shuffles; it stays exact.

33. **An exponential cost against a linear multiplier never levels off.** Prefer polynomial costs, and add a pacing test that bounds the time per step.

34. **Every check needs a test that proves it can fail.** A check that can't fail proves nothing. When adding one, add a broken input that trips it.

## Editing

35. **Scripted edits must assert that they matched.** A `str.replace` silently did nothing after StyLua reformatted the target. Every scripted replace does `assert old in s` first.

36. **Write long edit scripts to a file instead of inlining them in a shell heredoc.** Big inline edits fail on shell quoting before anything runs.
