import AppKit
import CoreLocation
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate, CLLocationManagerDelegate {
    private let trayIdentifier = NSTouchBarItem.Identifier("CodexTouchBar.anchor")
    private let usageIdentifier = NSTouchBarItem.Identifier("CodexTouchBar.usage")
    private let cardWidth: CGFloat = 286
    private let farmWidth: CGFloat = 360
    private let animationFrame = 1.0 / 30.0
    private let refreshQueue = DispatchQueue(label: "CodexTouchBar.refresh", qos: .utility)
    private let touchBar = NSTouchBar()
    private let usageClient = CodexUsageClient()
    private let weatherClient = WeatherClient()
    private lazy var usageRenderer = UsageRenderer(width: cardWidth)
    private lazy var farmScene = FarmScene(
        width: farmWidth,
        tileWidth: 288,
        frameDuration: animationFrame
    )
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        return manager
    }()

    private var trayItem: NSCustomTouchBarItem?
    private var statusItem: NSStatusItem?
    private var codexStatusMenuItem: NSMenuItem?
    private var weatherStatusMenuItem: NSMenuItem?
    private var touchBarView: NSView?
    private var usageButton: NSButton?
    private var farmButton: NSButton?
    private var usageTimer: Timer?
    private var weatherTimer: Timer?
    private var farmAnimationTimer: Timer?
    private var isRefreshing = false
    private var tappedRefresh = false
    private var currentUsage: Usage?
    private var weatherCoordinate: CLLocationCoordinate2D?
    private var isFetchingWeather = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ControlStrip.isSupported else {
            fputs("This macOS version does not expose the Touch Bar Control Strip API.\n", stderr)
            NSApp.terminate(nil)
            return
        }

        let usageButton = NSButton(
            image: usageRenderer.image(nil),
            target: self,
            action: #selector(cardTapped)
        )
        usageButton.frame = NSRect(x: 0, y: 0, width: cardWidth, height: 30)
        usageButton.isBordered = false
        usageButton.imagePosition = .imageOnly
        usageButton.imageScaling = .scaleNone
        usageButton.toolTip = "Tap to refresh Codex usage."
        usageButton.setAccessibilityLabel("Codex remaining usage")

        let farmButton = NSButton(image: farmScene.frameImage(), target: nil, action: nil)
        farmButton.frame = NSRect(x: cardWidth, y: 0, width: farmWidth, height: 30)
        farmButton.isBordered = false
        farmButton.imagePosition = .imageOnly
        farmButton.imageScaling = .scaleNone
        let farmTap = NSClickGestureRecognizer(target: self, action: #selector(farmTapped))
        farmTap.allowedTouchTypes = .direct
        farmButton.addGestureRecognizer(farmTap)
        farmButton.toolTip = "Farm life roams in fair daylight. Tap for local weather."
        farmButton.setAccessibilityLabel("Live-weather farm")

        let touchBarView = NSView(
            frame: NSRect(x: 0, y: 0, width: cardWidth + farmWidth, height: 30)
        )
        touchBarView.addSubview(usageButton)
        touchBarView.addSubview(farmButton)
        self.usageButton = usageButton
        self.farmButton = farmButton
        self.touchBarView = touchBarView

        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [usageIdentifier]
        NSApp.touchBar = touchBar

        let trayItem = NSCustomTouchBarItem(identifier: trayIdentifier)
        trayItem.view = NSButton(
            image: NSImage(
                systemSymbolName: "chevron.left",
                accessibilityDescription: "Show Codex usage"
            )!,
            target: self,
            action: #selector(showTouchBar)
        )
        self.trayItem = trayItem
        ControlStrip.add(trayItem)
        installMenuBar()

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            workspaceNotifications.addObserver(
                self,
                selector: #selector(restoreTouchBar),
                name: name,
                object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restoreTouchBar),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        scheduleTouchBarRestore(after: 0.5)

        refresh()
        refreshLocationIfAuthorized()
        updateFarmAnimation()
        if farmScene.maybeStartRareEvent() {
            updateFarmAnimation()
            updateFarmImage()
        }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateFarmForClock()
            if self.farmScene.maybeStartRareEvent() {
                self.updateFarmAnimation()
                self.updateFarmImage()
            }
            self.refresh()
        }
        weatherTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.refreshWeather()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageTimer?.invalidate()
        weatherTimer?.invalidate()
        farmAnimationTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        ControlStrip.dismiss(touchBar)
        if let trayItem { ControlStrip.remove(trayItem) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard identifier == usageIdentifier, let touchBarView else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = touchBarView
        return item
    }

    private func installMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌾"
        statusItem.button?.toolTip = "Codex Touch Bar"
        statusItem.button?.setAccessibilityLabel("Codex farm controls")

        let menu = NSMenu(title: "Codex Touch Bar")
        let codexStatus = NSMenuItem(title: "Codex: Loading…", action: nil, keyEquivalent: "")
        codexStatus.isEnabled = false
        menu.addItem(codexStatus)
        let weatherStatus = NSMenuItem(
            title: "Weather: Waiting for location",
            action: nil,
            keyEquivalent: ""
        )
        weatherStatus.isEnabled = false
        menu.addItem(weatherStatus)
        menu.addItem(.separator())

        let refreshCodex = NSMenuItem(
            title: "Refresh Codex",
            action: #selector(cardTapped),
            keyEquivalent: "r"
        )
        refreshCodex.target = self
        menu.addItem(refreshCodex)
        let refreshWeather = NSMenuItem(
            title: "Refresh Weather",
            action: #selector(refreshWeatherFromMenu),
            keyEquivalent: ""
        )
        refreshWeather.target = self
        menu.addItem(refreshWeather)

        let farmMenu = NSMenu(title: "Farm Appearance")
        let farmOptions: [(String, FarmPeriod?)] = [
            ("Automatic", nil), ("Dawn", .dawn), ("Day", .day),
            ("Dusk", .dusk), ("Night", .night)
        ]
        for (title, period) in farmOptions {
            let item = NSMenuItem(
                title: title,
                action: #selector(selectFarmPeriod(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = period?.rawValue
            item.state = period == nil ? .on : .off
            farmMenu.addItem(item)
        }
        let farmItem = NSMenuItem(title: "Farm Appearance", action: nil, keyEquivalent: "")
        farmItem.submenu = farmMenu
        menu.addItem(farmItem)

        let weatherMenu = NSMenu(title: "Weather")
        let weatherOptions: [(String, WeatherCondition?)] = [
            ("Live Weather", nil), ("Clear", .clear), ("Cloudy", .cloudy),
            ("Fog", .fog), ("Rain", .rain), ("Snow", .snow),
            ("Thunderstorm", .thunderstorm)
        ]
        for (title, condition) in weatherOptions {
            let item = NSMenuItem(
                title: title,
                action: #selector(selectWeather(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = condition?.rawValue
            item.state = condition == nil ? .on : .off
            weatherMenu.addItem(item)
        }
        let weatherItem = NSMenuItem(title: "Weather", action: nil, keyEquivalent: "")
        weatherItem.submenu = weatherMenu
        menu.addItem(weatherItem)

        let lifeMenu = NSMenu(title: "Farm Life")
        for (title, tag) in [("Automatic", -1), ("Show", 1), ("Hide", 0)] {
            let item = NSMenuItem(
                title: title,
                action: #selector(selectFarmLife(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = tag
            item.state = tag == -1 ? .on : .off
            lifeMenu.addItem(item)
        }
        let lifeItem = NSMenuItem(title: "Farm Life", action: nil, keyEquivalent: "")
        lifeItem.submenu = lifeMenu
        menu.addItem(lifeItem)

        menu.addItem(.separator())
        let showTouchBar = NSMenuItem(
            title: "Show Touch Bar",
            action: #selector(showTouchBar),
            keyEquivalent: ""
        )
        showTouchBar.target = self
        menu.addItem(showTouchBar)
        let quit = NSMenuItem(
            title: "Quit Codex Touch Bar",
            action: #selector(terminateFromMenu),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        self.statusItem = statusItem
        codexStatusMenuItem = codexStatus
        weatherStatusMenuItem = weatherStatus
        updateMenuBar()
    }

    private func updateMenuBar() {
        if let currentUsage {
            codexStatusMenuItem?.title = "Codex: \(currentUsage.remainingPercent)% remaining · \(currentUsage.detailLabel)"
        } else {
            codexStatusMenuItem?.title = "Codex: Loading…"
        }
        if let currentWeather = farmScene.currentWeather {
            let temperature = Int(currentWeather.temperature.rounded())
            let condition = farmScene.weatherOverride ?? currentWeather.condition
            let preview = farmScene.weatherOverride == nil ? "" : " preview"
            weatherStatusMenuItem?.title = "Weather: \(temperature)°C · \(condition.label)\(preview)"
            statusItem?.button?.title = "🌾 \(temperature)°"
        } else if let weatherOverride = farmScene.weatherOverride {
            weatherStatusMenuItem?.title = "Weather preview: \(weatherOverride.label)"
            statusItem?.button?.title = "🌾"
        } else {
            weatherStatusMenuItem?.title = "Weather: Waiting for location"
            statusItem?.button?.title = "🌾"
        }
    }

    private func markSelected(_ sender: NSMenuItem) {
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }

    @objc private func selectFarmPeriod(_ sender: NSMenuItem) {
        let period = (sender.representedObject as? String).flatMap(FarmPeriod.init(rawValue:))
        farmScene.setPeriodOverride(period)
        markSelected(sender)
        updateFarmAnimation()
        updateFarmImage()
    }

    @objc private func selectWeather(_ sender: NSMenuItem) {
        let weather = (sender.representedObject as? String).flatMap(WeatherCondition.init(rawValue:))
        farmScene.setWeatherOverride(weather)
        markSelected(sender)
        updateFarmAnimation()
        updateFarmImage()
        updateFarmMetadata()
        if farmScene.weatherOverride == nil { requestWeatherAccessIfNeeded() }
    }

    @objc private func selectFarmLife(_ sender: NSMenuItem) {
        farmScene.setLifeOverride(sender.tag == -1 ? nil : sender.tag == 1)
        markSelected(sender)
        updateFarmAnimation()
        updateFarmImage()
    }

    @objc private func refreshWeatherFromMenu() {
        requestWeatherAccessIfNeeded()
    }

    @objc private func terminateFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshQueue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.usageClient.fetch() }
            DispatchQueue.main.async { self.apply(result) }
        }
    }

    @objc private func cardTapped() {
        guard !isRefreshing else { return }
        let image = usageButton?.image ?? usageRenderer.image(nil)
        tappedRefresh = true
        refresh()
        animateRefresh(image)
    }

    @objc private func farmTapped(_ gesture: NSClickGestureRecognizer) {
        requestWeatherAccessIfNeeded()
    }

    @objc private func showTouchBar() {
        ControlStrip.present(touchBar, from: trayIdentifier)
    }

    @objc private func restoreTouchBar(_ notification: Notification) {
        updateFarmForClock()
        if notification.name == NSWorkspace.didWakeNotification {
            refreshLocationIfAuthorized()
        }
        scheduleTouchBarRestore(after: 0.3)
    }

    private func updateFarmForClock() {
        guard farmScene.updateClock() else { return }
        updateFarmAnimation()
        updateFarmImage()
    }

    private func scheduleTouchBarRestore(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.showTouchBar()
        }
    }

    private func requestWeatherAccessIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if weatherCoordinate == nil {
                locationManager.requestLocation()
            } else {
                refreshWeather()
            }
        default:
            updateFarmMetadata()
        }
    }

    private func refreshLocationIfAuthorized() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            updateFarmMetadata()
        }
        if manager.authorizationStatus != .notDetermined {
            scheduleTouchBarRestore(after: 0.3)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        weatherCoordinate = coordinate
        fetchWeather(at: coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code != .locationUnknown {
            NSLog("Codex Touch Bar location failed: %@", error.localizedDescription)
        }
        updateFarmMetadata()
    }

    private func refreshWeather() {
        if let weatherCoordinate {
            fetchWeather(at: weatherCoordinate)
        } else {
            refreshLocationIfAuthorized()
        }
    }

    private func fetchWeather(at coordinate: CLLocationCoordinate2D) {
        guard !isFetchingWeather else { return }
        isFetchingWeather = true
        weatherClient.fetch(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingWeather = false
                switch result {
                case .success(let weather):
                    self.farmScene.applyWeather(weather)
                    self.updateFarmAnimation()
                    self.updateFarmImage()
                    self.updateFarmMetadata()
                case .failure(let error):
                    NSLog("Codex Touch Bar weather failed: %@", error.localizedDescription)
                }
            }
        }
    }

    private func updateFarmAnimation() {
        guard farmScene.requiresAnimation else {
            farmAnimationTimer?.invalidate()
            farmAnimationTimer = nil
            return
        }
        guard farmAnimationTimer == nil else { return }
        let timer = Timer(timeInterval: animationFrame, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.farmScene.advance()
            self.updateFarmImage()
            self.updateFarmAnimation()
        }
        RunLoop.main.add(timer, forMode: .common)
        farmAnimationTimer = timer
    }

    private func updateFarmImage() {
        farmButton?.image = farmScene.frameImage()
    }

    private func updateFarmMetadata() {
        defer { updateMenuBar() }
        if let currentWeather = farmScene.currentWeather,
           let displayedWeather = farmScene.displayedWeather {
            let temperature = Int(currentWeather.temperature.rounded())
            farmButton?.toolTip = "\(temperature)°C · \(displayedWeather.condition.label). Farm life roams in fair daylight. Weather data by Open-Meteo.com."
            farmButton?.setAccessibilityValue(
                "\(temperature) degrees Celsius, \(displayedWeather.condition.label)"
            )
        } else if let weatherOverride = farmScene.weatherOverride {
            farmButton?.toolTip = "\(weatherOverride.label) preview. Tap for live weather."
            farmButton?.setAccessibilityValue("\(weatherOverride.label) weather preview")
        } else if [.denied, .restricted].contains(locationManager.authorizationStatus) {
            farmButton?.toolTip = "Farm life roams in fair daylight. Location is off."
            farmButton?.setAccessibilityValue("Clock-based farm; location unavailable")
        } else {
            farmButton?.toolTip = "Farm life roams in fair daylight. Tap for local weather."
            farmButton?.setAccessibilityValue("Clock-based farm; weather not loaded")
        }
    }

    private func apply(_ result: Result<Usage, Error>) {
        switch result {
        case .success(let usage):
            let previous = currentUsage
            let sparkle = tappedRefresh
            currentUsage = usage
            updateMenuBar()
            tappedRefresh = false
            updateFarmImage()
            if let previous {
                animateUsage(from: previous, to: usage, sparkle: sparkle)
            } else {
                usageButton?.image = usageRenderer.image(usage)
                isRefreshing = false
            }
            usageButton?.toolTip = "\(usage.remainingPercent)% Codex usage remaining. Tap to refresh."
            usageButton?.setAccessibilityValue("\(usage.remainingPercent) percent remaining")
        case .failure(let error):
            usageButton?.image = usageRenderer.feedbackImage(
                usageButton?.image,
                text: "!  Refresh failed",
                color: .systemRed
            )
            usageButton?.toolTip = error.localizedDescription
            usageButton?.setAccessibilityValue("Unavailable")
            NSLog("Codex Touch Bar refresh failed: %@", error.localizedDescription)
            tappedRefresh = false
            updateFarmImage()
            isRefreshing = false
        }
    }

    private func animateUsage(
        from previous: Usage,
        to usage: Usage,
        progress: CGFloat = 0,
        sparkle: Bool
    ) {
        let percentages = usage.windows.map { window in
            let start = previous.windows.first { $0.slot == window.slot }?.remainingPercent
                ?? window.remainingPercent
            return interpolatedPercentage(
                from: start,
                to: window.remainingPercent,
                progress: progress
            )
        }
        usageButton?.image = usageRenderer.image(usage, remainingPercentages: percentages)
        guard progress < 1 else {
            if sparkle {
                animateSparkle(usage)
            } else {
                isRefreshing = false
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + animationFrame) { [weak self] in
            self?.animateUsage(
                from: previous,
                to: usage,
                progress: min(1, progress + 1.0 / 10.0),
                sparkle: sparkle
            )
        }
    }

    private func animateSparkle(_ usage: Usage, phase: CGFloat = 0) {
        guard phase < 1 else {
            usageButton?.image = usageRenderer.image(usage)
            isRefreshing = false
            return
        }
        let strength = CGFloat(sin(Double(phase) * .pi))
        usageButton?.image = usageRenderer.image(usage, sparkle: strength)
        DispatchQueue.main.asyncAfter(deadline: .now() + animationFrame) { [weak self] in
            self?.animateSparkle(usage, phase: phase + 1.0 / 10.0)
        }
    }

    private func animateRefresh(_ image: NSImage, phase: CGFloat = 0) {
        guard isRefreshing, tappedRefresh else { return }
        if let currentUsage {
            usageButton?.image = usageRenderer.image(currentUsage, cometPhase: phase)
        } else {
            usageButton?.image = usageRenderer.feedbackImage(
                image,
                text: "↻  Refreshing…",
                color: .systemBlue,
                shimmer: phase
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + animationFrame) { [weak self] in
            self?.animateRefresh(
                image,
                phase: (phase + 1.0 / 18.0).truncatingRemainder(dividingBy: 1)
            )
        }
    }
}
