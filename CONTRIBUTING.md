# Contributing

Thanks for helping keep TouchBar Cozy Farm useful and cozy. The project stays
intentionally small: one native Swift executable, no third-party dependencies,
and one command that checks both supported build paths.

## Requirements

- macOS 13 or newer
- Xcode command-line tools
- A MacBook Pro with a Touch Bar for final UI verification
- A signed-in Codex CLI for live usage checks

## Local workflow

Run the complete contributor check before opening a pull request:

```sh
make check
```

The available commands are:

| Command | Purpose |
| --- | --- |
| `make build` | Compile the optimized standalone executable. |
| `make test` | Build it and run the built-in self-tests. |
| `make check` | Test both the Makefile and Swift Package build paths. |
| `make install` | Build, test, install, and restart the user LaunchAgent. |
| `make status` | Fetch and print current Codex usage. |
| `make uninstall` | Remove the installed app and LaunchAgent. |

Use `make install` only when you are ready to replace your currently installed
copy. Run `make status` afterward to confirm the installed workflow still works.

## Where changes belong

| Area | Responsibility |
| --- | --- |
| `App/` | Touch Bar and menu creation, timers, location authorization, and feature coordination. |
| `Features/Usage/` | Usage models, Codex app-server communication, and usage-card rendering. |
| `Features/Farm/` | Farm and weather models, Open-Meteo communication, scene state, animation, and rendering. |
| `Platform/` | Private Control Strip symbols and resource-bundle lookup. |
| `Diagnostics/` | Pure parser, layout, animation, weather, and resource regression checks. |
| `Resources/` | Time-of-day farm scenes and the sprite atlas. |

Keep these boundaries boring:

- Domain models must not depend on AppKit, Core Location, `Process`, or
  `URLSession`. CoreGraphics value types such as `CGFloat` are fine.
- Concrete clients own external I/O and return domain values.
- Renderers and `FarmScene` own drawing and visual state.
- `AppDelegate` coordinates concrete features; do not move parsing, networking,
  or drawing into it.
- Add a protocol, package target, or dependency only when a real second
  implementation or platform needs it.
- Keep cross-file APIs module-internal and make implementation details `private`.

## Testing changes

Add the smallest regression assertion to the matching Usage or Farm group in
`Diagnostics/SelfTest.swift` when changing parsing, model formatting, layout
math, weather mapping, animation movement, rare events, or resource lookup.

GitHub Actions and `make check` can verify compilation and deterministic
self-tests. They cannot verify the private Control Strip integration, location
permission prompts, live weather, or physical Touch Bar rendering. For those
changes, install the app and manually check:

- Codex refresh and long model-name layout
- Farm animation and menu previews
- Location allowed, denied, and previously allowed flows
- Weather refresh and failure fallback
- Touch Bar restoration after switching apps or waking the Mac

## Farm assets

The four farm scenes are 2x assets: **576x60 pixels**, rendered as repeating
**288x30-point** tiles. Keep their left and right edges seamless.

`farm-sprites.png` is a sprite atlas. Replacing or rearranging it requires
updating the corresponding source rectangles in `FarmScene.swift`. Keep alpha
transparency and verify the result on the physical Touch Bar; a desktop preview
does not reproduce its scaling and brightness exactly.
