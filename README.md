<h1 align="center">🌾 TouchBar Cozy Farm</h1>

<p align="center">
  A tiny live-weather farm and Codex usage monitor for the MacBook Pro Touch Bar.
</p>

<p align="center">
  <a href="https://github.com/MixPiyadanai/touchbar-cozy-farm/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/MixPiyadanai/touchbar-cozy-farm?style=flat-square"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-000000?style=flat-square&logo=apple&logoColor=white">
  <img alt="Native Swift" src="https://img.shields.io/badge/Swift-native-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="No weather API key" src="https://img.shields.io/badge/weather-no_API_key-4A90E2?style=flat-square">
</p>

## A tiny world above your keyboard

These are the actual farm scenes bundled with the app—not mockups.

<p align="center">
  <img src="Sources/CodexTouchBar/Resources/farm-dawn.png" width="360" alt="Cozy farm at dawn">
  <img src="Sources/CodexTouchBar/Resources/farm-day.png" width="360" alt="Cozy farm during the day">
  <br>
  <img src="Sources/CodexTouchBar/Resources/farm-dusk.png" width="360" alt="Cozy farm at dusk">
  <img src="Sources/CodexTouchBar/Resources/farm-night.png" width="360" alt="Cozy farm at night">
</p>

The farm follows your local clock and crossfades through dawn, day, dusk, and
night. With location permission it also reacts to current weather with moving
clouds, dense fog, rain, snow, and thunderstorms.

## What lives in the Touch Bar

- **Codex at a glance** — current model, remaining 5-hour/weekly limits,
  progress bars, and reset countdowns.
- **A living farm** — animals wander, pause, turn around, and shelter at night
  or during bad weather. A tractor rolls through the fields with them.
- **Real local weather** — approximate Core Location plus Open-Meteo, refreshed
  every 15 minutes with no weather API key.
- **Rare cozy moments** — rainbows after rain, fireflies at dusk, and shooting
  stars at night.
- **Menu-bar controls** — refresh Codex or weather, preview any time/weather,
  show or hide farm life, restore the Touch Bar, or quit.
- **Persistent presence** — keeps the card available beside the normal macOS
  Control Strip and can start automatically at login.

## Controls

| Place | Action |
| --- | --- |
| Codex card | Tap to refresh usage. Repeated taps are safely ignored while refreshing. |
| Farm | Tap to request approximate location or refresh live weather. |
| Menu-bar wheat icon | Open appearance, weather, farm-life, refresh, and quit controls. |
| Control Strip chevron | Bring the custom card back when macOS hides it. |

## Install

### From the release

1. Download the `CodexTouchBar-*.zip` asset from the
   [latest release](https://github.com/MixPiyadanai/touchbar-cozy-farm/releases/latest).
2. Unzip it and move `CodexTouchBar.app` to `~/Applications`.
3. Open the app.

The downloadable app is ad-hoc signed rather than Apple-notarized. If Gatekeeper
blocks the first launch, right-click the app and choose **Open**.

### From source — recommended for start at login

```sh
git clone https://github.com/MixPiyadanai/touchbar-cozy-farm.git
cd touchbar-cozy-farm
make install
```

`make install` builds, tests, installs, launches, and creates a user LaunchAgent.

```sh
make status      # print current Codex usage
make uninstall   # remove the app and LaunchAgent
```

## Project layout

```text
Sources/CodexTouchBar/
├── main.swift          # CLI dispatch and app startup
├── App/                # Touch Bar, menu, location, and lifecycle coordination
├── Features/Usage/     # Codex models, app-server client, and card renderer
├── Features/Farm/      # farm models, weather client, scene state, and renderer
├── Platform/           # Control Strip bridge and resource bundle
├── Diagnostics/        # feature self-tests
└── Resources/          # farm scenes and sprites
Config/Info.plist    # macOS bundle configuration
Package.swift        # standard Swift package manifest
Makefile             # app bundling and LaunchAgent install
```

## Contributing

Run `make check` before submitting a change. See [CONTRIBUTING.md](CONTRIBUTING.md)
for the architecture boundaries, local workflow, testing limits, and farm asset
requirements.

## Requirements

- A MacBook Pro with a Touch Bar
- macOS 13 or newer
- Xcode command-line tools
- A signed-in Codex CLI
- Internet and optional approximate location permission for live weather

## Privacy and data

Codex usage comes from the authenticated local Codex app server. The utility
does not read or store your credentials. Weather uses approximate macOS
location and sends only coordinates to Open-Meteo; denying location simply
keeps the clock-based farm.

Weather data is provided by [Open-Meteo.com](https://open-meteo.com/) under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

<details>
<summary>Why does it use private Touch Bar symbols?</summary>

The public AppKit Touch Bar API only controls the frontmost app's bar. A
persistent Control Strip item requires guarded private macOS symbols. If Apple
removes them in a future macOS release, the app exits instead of crashing.

</details>

## License

See [LICENSE](LICENSE).
