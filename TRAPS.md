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

## Git

31. **Pin LF line endings in `.gitattributes`.** With `core.autocrlf` on Windows, Git would check files out as CRLF, and `stylua --check` (`line_endings = "Unix"`) would fail on every fresh clone.

## Numbers and checks

32. **Keep integer math under 2^53.** Use MINSTD (`seed * 48271 % 2147483647`) for seeded shuffles; it stays exact.

33. **An exponential cost against a linear multiplier never levels off.** Prefer polynomial costs, and add a pacing test that bounds the time per step.

34. **Every check needs a test that proves it can fail.** A check that can't fail proves nothing. When adding one, add a broken input that trips it.

## Editing

35. **Scripted edits must assert that they matched.** A `str.replace` silently did nothing after StyLua reformatted the target. Every scripted replace does `assert old in s` first.

36. **Write long edit scripts to a file instead of inlining them in a shell heredoc.** Big inline edits fail on shell quoting before anything runs.
