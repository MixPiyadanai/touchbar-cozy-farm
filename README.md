# Codex Touch Bar

Shows Codex as a persistent standalone Touch Bar card with the current model,
up to two real rate-limit windows, remaining bars, percentages, and reset
countdowns. The normal macOS Control Strip stays on the right with a small
chevron required by macOS to restore the card. It refreshes every minute; tap
the Codex card to refresh immediately. Animals and a tractor roam the fixed
farm in fair dawn/daylight, then shelter at dusk, night, and in bad weather.
Tap the farm to enable or refresh current local weather.
Rare fair-weather moments include rainbows after rain, dusk fireflies, and
nighttime shooting stars.

The macOS menu-bar item shows live temperature and provides Codex/weather
refresh, temporary farm and weather previews, farm-life visibility, Touch Bar
restore, and Quit controls. Preview choices reset to Auto/Live at launch.

It reads the authenticated `account/rateLimits/read` snapshot from the local
Codex app server. It does not read credentials or require an API key.

Weather uses approximate macOS location after a one-time permission prompt and
refreshes every 15 minutes. Weather data is provided by
[Open-Meteo.com](https://open-meteo.com/) under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

```sh
make install   # build, test, install, launch, and start at login
make status    # print the current value
make uninstall
```

Requires a Touch Bar Mac, macOS 13+, Xcode, and a signed-in Codex CLI.

The public AppKit Touch Bar API only controls the frontmost app's bar, so the
persistent Control Strip item uses guarded private macOS symbols. If Apple
removes them in a future release, the app exits instead of crashing.
