import AppKit
import CoreLocation
import Darwin
import Foundation

func codexGlyphAlpha(brightness: CGFloat, chroma: CGFloat) -> CGFloat {
    let blue = (chroma - 0.05) / 0.15
    let white = (brightness - 0.72) / 0.18
    return min(1, max(0, max(blue, white)))
}

func interpolatedPercentage(from: Int, to: Int, progress: CGFloat) -> CGFloat {
    CGFloat(from) + CGFloat(to - from) * easedProgress(progress)
}

func easedProgress(_ progress: CGFloat) -> CGFloat {
    let progress = min(1, max(0, progress))
    return progress * progress * (3 - 2 * progress)
}

func cometOffset(width: CGFloat, phase: CGFloat) -> CGFloat {
    width * min(1, max(0, phase))
}

func wrappedOffset(_ offset: CGFloat, width: CGFloat) -> CGFloat {
    let offset = offset.truncatingRemainder(dividingBy: width)
    return offset < 0 ? offset + width : offset
}

func nextAnimalStep(
    phase: CGFloat,
    pauseTicks: Int,
    movingLeft: Bool,
    pauseFor: Int?,
    speed: CGFloat = 0.006
) -> (phase: CGFloat, pauseTicks: Int) {
    if pauseTicks > 0 { return (phase, pauseTicks - 1) }
    if let pauseFor { return (phase, max(0, pauseFor)) }
    return (wrappedOffset(phase + (movingLeft ? -speed : speed), width: 1), 0)
}

enum FarmPeriod: String {
    case dawn, day, dusk, night
}

func farmPeriod(at hour: Int) -> FarmPeriod {
    switch hour {
    case 5..<8: return .dawn
    case 8..<17: return .day
    case 17..<20: return .dusk
    default: return .night
    }
}

func cloudTint(for period: FarmPeriod) -> NSColor {
    switch period {
    case .dawn:
        NSColor(calibratedRed: 1, green: 0.68, blue: 0.45, alpha: 0.22)
    case .day:
        .clear
    case .dusk:
        NSColor(calibratedRed: 0.65, green: 0.38, blue: 0.55, alpha: 0.45)
    case .night:
        NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.34, alpha: 0.68)
    }
}

enum WeatherCondition: String {
    case clear, cloudy, fog, rain, snow, thunderstorm

    var label: String {
        switch self {
        case .clear: "Clear"
        case .cloudy: "Cloudy"
        case .fog: "Foggy"
        case .rain: "Rain"
        case .snow: "Snow"
        case .thunderstorm: "Thunderstorm"
        }
    }

    var isAnimated: Bool { self != .clear }
}

enum RareFarmEvent {
    case rainbow, fireflies, shootingStar
}

func rareFarmEventIsAllowed(
    _ event: RareFarmEvent,
    period: FarmPeriod,
    weather: WeatherCondition?
) -> Bool {
    let isFair = weather == nil || weather == .clear || weather == .cloudy
    guard isFair else { return false }
    switch event {
    case .rainbow: return period == .dawn || period == .day
    case .fireflies: return period == .dusk
    case .shootingStar: return period == .night
    }
}

func shouldShowRainbow(
    from previous: WeatherCondition?,
    to current: WeatherCondition,
    period: FarmPeriod
) -> Bool {
    [.rain, .thunderstorm].contains(previous)
        && [.clear, .cloudy].contains(current)
        && rareFarmEventIsAllowed(.rainbow, period: period, weather: current)
}

func farmLifeIsVisible(period: FarmPeriod, weather: WeatherCondition?) -> Bool {
    guard period == .dawn || period == .day else { return false }
    return weather == nil || weather == .clear || weather == .cloudy
}

func weatherCondition(for code: Int) -> WeatherCondition {
    switch code {
    case 0: .clear
    case 1...3: .cloudy
    case 45, 48: .fog
    case 51...67, 80...82: .rain
    case 71...77, 85, 86: .snow
    case 95...99: .thunderstorm
    default: .cloudy
    }
}

struct WeatherState {
    let temperature: Double
    let condition: WeatherCondition
    let precipitation: Double
    let snowfall: Double
    let cloudCover: Double
    let isDay: Bool
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int
        let precipitation: Double
        let snowfall: Double
        let cloudCover: Double
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitation
            case snowfall
            case cloudCover = "cloud_cover"
            case isDay = "is_day"
        }
    }

    let current: Current
}

func parseWeather(_ data: Data) throws -> WeatherState {
    let current = try JSONDecoder().decode(OpenMeteoResponse.self, from: data).current
    return WeatherState(
        temperature: current.temperature,
        condition: weatherCondition(for: current.weatherCode),
        precipitation: current.precipitation,
        snowfall: current.snowfall,
        cloudCover: current.cloudCover,
        isDay: current.isDay == 1
    )
}

struct UsageWindow {
    let slot: String
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Int {
        Int(max(0, min(100, 100 - usedPercent)).rounded())
    }

    var label: String {
        guard let durationMinutes else { return slot == "primary" ? "5h" : "Wk" }
        switch durationMinutes {
        case 250...350: return "5h"
        case 9_500...11_000: return "Wk"
        case 42_000...45_000: return "Mo"
        case 60...1_439: return "\(durationMinutes / 60)h"
        default: return "\(max(1, durationMinutes / 1_440))d"
        }
    }
}

struct Usage {
    let windows: [UsageWindow]
    let model: String?
    let planType: String?

    var remainingPercent: Int {
        windows.map(\.remainingPercent).min() ?? 0
    }

    var detailLabel: String {
        let plan = planType?
            .replacingOccurrences(of: "chatgpt_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        guard let model else { return plan ?? "Loading…" }
        let name = model
            .replacingOccurrences(of: "gpt-", with: "")
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: "-")
        return plan.map { "\(name) · \($0)" } ?? name
    }
}

enum UsageError: LocalizedError {
    case codexNotFound
    case invalidResponse
    case appServerFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            "Codex CLI not found"
        case .invalidResponse:
            "Codex returned no rate-limit data"
        case .appServerFailed(let status):
            "Codex app server exited with status \(status)"
        }
    }
}

enum CodexUsage {
    static func fetch() throws -> Usage {
        guard let executable = codexExecutable() else { throw UsageError.codexNotFound }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(executable.deletingLastPathComponent().path):\(environment["PATH"] ?? "")"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
            if process.isRunning { process.terminate() }
        }

        let initialize = """
        {"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex-touch-bar","title":"Codex Touch Bar","version":"1.0.0"},"capabilities":{"experimentalApi":true,"requestAttestation":false}}}

        """
        input.fileHandleForWriting.write(Data(initialize.utf8))
        _ = try readResponse(id: 1, from: output.fileHandleForReading)

        let rateLimits = """
        {"method":"initialized"}
        {"method":"account/rateLimits/read","id":2}

        """
        input.fileHandleForWriting.write(Data(rateLimits.utf8))
        let data = try readResponse(id: 2, from: output.fileHandleForReading)

        let config = """
        {"method":"config/read","id":3,"params":{"includeLayers":false}}

        """
        input.fileHandleForWriting.write(Data(config.utf8))
        let configData = try? readResponse(id: 3, from: output.fileHandleForReading)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UsageError.appServerFailed(process.terminationStatus)
        }
        return try parse(data, configData: configData)
    }

    static func parse(_ data: Data, configData: Data? = nil) throws -> Usage {
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard
                let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                (message["id"] as? NSNumber)?.intValue == 2,
                let result = message["result"] as? [String: Any]
            else { continue }

            let fallback = result["rateLimits"] as? [String: Any]
            let byID = result["rateLimitsByLimitId"] as? [String: Any]
            let limits = (byID?["codex"] as? [String: Any]) ?? fallback
            let windows = ["primary", "secondary"].compactMap { name -> UsageWindow? in
                guard
                    let window = limits?[name] as? [String: Any],
                    let used = window["usedPercent"] as? NSNumber
                else { return nil }
                let duration = (window["windowDurationMins"] as? NSNumber)?.intValue
                let reset = (window["resetsAt"] as? NSNumber).map {
                    Date(timeIntervalSince1970: $0.doubleValue)
                }
                return UsageWindow(
                    slot: name,
                    usedPercent: used.doubleValue,
                    durationMinutes: duration,
                    resetsAt: reset
                )
            }
            guard !windows.isEmpty else { throw UsageError.invalidResponse }
            return Usage(
                windows: windows,
                model: model(from: configData),
                planType: limits?["planType"] as? String
            )
        }
        throw UsageError.invalidResponse
    }

    private static func model(from data: Data?) -> String? {
        guard
            let data,
            let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = message["result"] as? [String: Any],
            let config = result["config"] as? [String: Any]
        else { return nil }
        return config["model"] as? String
    }

    private static func codexExecutable() -> URL? {
        let fileManager = FileManager.default
        var paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            paths += path.split(separator: ":").map { "\($0)/codex" }
        }
        return paths.first(where: fileManager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    private static func readResponse(id: Int, from handle: FileHandle) throws -> Data {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            guard !chunk.isEmpty else { throw UsageError.invalidResponse }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard
                    let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    (message["id"] as? NSNumber)?.intValue == id
                else { continue }
                return line
            }
        }
    }
}

// ponytail: persistent Control Strip items require private API; fall back to
// BetterTouchTool if Apple removes these symbols in a future macOS release.
enum ControlStrip {
    private typealias PresenceFunction = @convention(c) (NSString, Bool) -> Void
    private typealias CloseBoxFunction = @convention(c) (Bool) -> Void
    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation",
        RTLD_NOW
    )

    static var isSupported: Bool {
        handle != nil && (NSTouchBarItem.self as AnyObject).responds(
            to: NSSelectorFromString("addSystemTrayItem:")
        )
    }

    static func add(_ item: NSTouchBarItem) {
        let selector = NSSelectorFromString("addSystemTrayItem:")
        guard isSupported else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(selector, with: item)
        setPresent(item.identifier, true)
    }

    static func remove(_ item: NSTouchBarItem) {
        setPresent(item.identifier, false)
        let selector = NSSelectorFromString("removeSystemTrayItem:")
        guard (NSTouchBarItem.self as AnyObject).responds(to: selector) else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(selector, with: item)
    }

    static func present(_ touchBar: NSTouchBar, from identifier: NSTouchBarItem.Identifier) {
        symbol("DFRSystemModalShowsCloseBoxWhenFrontMost", as: CloseBoxFunction.self)?(false)
        for name in [
            "presentSystemModalTouchBar:systemTrayItemIdentifier:",
            "presentSystemModalFunctionBar:systemTrayItemIdentifier:"
        ] {
            let selector = NSSelectorFromString(name)
            guard (NSTouchBar.self as AnyObject).responds(to: selector) else { continue }
            _ = (NSTouchBar.self as AnyObject).perform(selector, with: touchBar, with: identifier.rawValue)
            return
        }
    }

    static func dismiss(_ touchBar: NSTouchBar) {
        for name in ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"] {
            let selector = NSSelectorFromString(name)
            guard (NSTouchBar.self as AnyObject).responds(to: selector) else { continue }
            _ = (NSTouchBar.self as AnyObject).perform(selector, with: touchBar)
            return
        }
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private static func setPresent(_ identifier: NSTouchBarItem.Identifier, _ present: Bool) {
        guard let handle, let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else {
            return
        }
        let function = unsafeBitCast(symbol, to: PresenceFunction.self)
        function(identifier.rawValue as NSString, present)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate, CLLocationManagerDelegate {
    private let trayIdentifier = NSTouchBarItem.Identifier("CodexTouchBar.anchor")
    private let usageIdentifier = NSTouchBarItem.Identifier("CodexTouchBar.usage")
    private let cardWidth: CGFloat = 286
    private let farmWidth: CGFloat = 360
    private let farmTileWidth: CGFloat = 288
    private let refreshQueue = DispatchQueue(label: "CodexTouchBar.refresh", qos: .utility)
    private let animationFrame = 1.0 / 30.0
    private let touchBar = NSTouchBar()
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        return manager
    }()
    private lazy var codexIcon: NSImage? = {
        guard let source = NSImage(
            contentsOfFile: "/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png"
        ) else { return nil }
        let size = NSSize(width: 256, height: 256)
        let cropped = NSImage(size: size)
        cropped.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(
                x: source.size.width * 0.17,
                y: source.size.height * 0.17,
                width: source.size.width * 0.66,
                height: source.size.height * 0.66
            ),
            operation: .sourceOver,
            fraction: 1
        )
        cropped.unlockFocus()
        guard
            let data = cropped.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data)
        else { return cropped }
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
                let chroma = brightness - min(color.redComponent, color.greenComponent, color.blueComponent)
                let alpha = color.alphaComponent * codexGlyphAlpha(brightness: brightness, chroma: chroma)
                bitmap.setColor(
                    NSColor(
                        deviceRed: color.redComponent,
                        green: color.greenComponent,
                        blue: color.blueComponent,
                        alpha: alpha
                    ),
                    atX: x,
                    y: y
                )
            }
        }
        let cleaned = NSImage(size: size)
        cleaned.addRepresentation(bitmap)
        return cleaned
    }()
    private var currentFarmPeriod = farmPeriod(
        at: Calendar.current.component(.hour, from: Date())
    )
    private lazy var farmArtwork = farmImage(currentFarmPeriod)
    private lazy var farmSprites: NSImage? = {
        guard
            let url = Bundle.main.url(forResource: "farm-sprites", withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }()
    private var cloudArtworkByPeriod: [String: NSImage] = [:]
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
    private var currentWeather: WeatherState?
    private var weatherCoordinate: CLLocationCoordinate2D?
    private var isFetchingWeather = false
    private var weatherPhase: CGFloat = 0
    private var cloudPhases: [CGFloat] = [0, 0.24, 0.51, 0.78]
    private var cloudSpeeds: [CGFloat] = [0.0025, 0.0015, 0.002, 0.0018]
    private var animalPhases: [CGFloat] = [0, 0.28, 0.54]
    private var animalSpeeds: [CGFloat] = [0.008, 0.0035, 0.005]
    private var animalPauseTicks = [0, 0, 0]
    private var animalMovingLeft = [false, true, true]
    private var rareFarmEvent: RareFarmEvent?
    private var rareFarmEventPhase: CGFloat = 0
    private var farmTransitionImage: NSImage?
    private var farmTransitionProgress: CGFloat = 1
    private var farmPeriodOverride: FarmPeriod?
    private var weatherOverride: WeatherCondition?
    private var farmLifeOverride: Bool?

    private var displayedFarmPeriod: FarmPeriod {
        farmPeriodOverride ?? currentFarmPeriod
    }

    private var displayedWeather: WeatherState? {
        guard let condition = weatherOverride ?? currentWeather?.condition else { return nil }
        return WeatherState(
            temperature: currentWeather?.temperature ?? 0,
            condition: condition,
            precipitation: currentWeather?.precipitation ?? 0,
            snowfall: currentWeather?.snowfall ?? 0,
            cloudCover: currentWeather?.cloudCover ?? 80,
            isDay: currentWeather?.isDay ?? true
        )
    }

    private var isFarmLifeVisible: Bool {
        farmLifeOverride ?? farmLifeIsVisible(
            period: displayedFarmPeriod,
            weather: displayedWeather?.condition
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ControlStrip.isSupported else {
            fputs("This macOS version does not expose the Touch Bar Control Strip API.\n", stderr)
            NSApp.terminate(nil)
            return
        }

        let usageButton = NSButton(image: usageImage(nil), target: self, action: #selector(cardTapped))
        usageButton.frame = NSRect(x: 0, y: 0, width: cardWidth, height: 30)
        usageButton.isBordered = false
        usageButton.imagePosition = .imageOnly
        usageButton.imageScaling = .scaleNone
        usageButton.toolTip = "Tap to refresh Codex usage."
        usageButton.setAccessibilityLabel("Codex remaining usage")

        let farmButton = NSButton(image: farmFrameImage(), target: nil, action: nil)
        farmButton.frame = NSRect(x: cardWidth, y: 0, width: farmWidth, height: 30)
        farmButton.isBordered = false
        farmButton.imagePosition = .imageOnly
        farmButton.imageScaling = .scaleNone
        let farmTap = NSClickGestureRecognizer(target: self, action: #selector(farmTapped))
        farmTap.allowedTouchTypes = .direct
        farmButton.addGestureRecognizer(farmTap)
        farmButton.toolTip = "Farm life roams in fair daylight. Tap for local weather."
        farmButton.setAccessibilityLabel("Live-weather farm")

        let touchBarView = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth + farmWidth, height: 30))
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
            image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Show Codex usage")!,
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
        maybeStartRareFarmEvent()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateFarmForClock()
            self.maybeStartRareFarmEvent()
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

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
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
        let weatherStatus = NSMenuItem(title: "Weather: Waiting for location", action: nil, keyEquivalent: "")
        weatherStatus.isEnabled = false
        menu.addItem(weatherStatus)
        menu.addItem(.separator())

        let refreshCodex = NSMenuItem(title: "Refresh Codex", action: #selector(cardTapped), keyEquivalent: "r")
        refreshCodex.target = self
        menu.addItem(refreshCodex)
        let refreshWeather = NSMenuItem(title: "Refresh Weather", action: #selector(refreshWeatherFromMenu), keyEquivalent: "")
        refreshWeather.target = self
        menu.addItem(refreshWeather)

        let farmMenu = NSMenu(title: "Farm Appearance")
        let farmOptions: [(String, FarmPeriod?)] = [
            ("Automatic", nil), ("Dawn", .dawn), ("Day", .day),
            ("Dusk", .dusk), ("Night", .night)
        ]
        for (title, period) in farmOptions {
            let item = NSMenuItem(title: title, action: #selector(selectFarmPeriod(_:)), keyEquivalent: "")
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
            let item = NSMenuItem(title: title, action: #selector(selectWeather(_:)), keyEquivalent: "")
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
            let item = NSMenuItem(title: title, action: #selector(selectFarmLife(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = tag == -1 ? .on : .off
            lifeMenu.addItem(item)
        }
        let lifeItem = NSMenuItem(title: "Farm Life", action: nil, keyEquivalent: "")
        lifeItem.submenu = lifeMenu
        menu.addItem(lifeItem)

        menu.addItem(.separator())
        let showTouchBar = NSMenuItem(title: "Show Touch Bar", action: #selector(showTouchBar), keyEquivalent: "")
        showTouchBar.target = self
        menu.addItem(showTouchBar)
        let quit = NSMenuItem(title: "Quit Codex Touch Bar", action: #selector(terminateFromMenu), keyEquivalent: "q")
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
        if let currentWeather {
            let temperature = Int(currentWeather.temperature.rounded())
            let condition = weatherOverride ?? currentWeather.condition
            let preview = weatherOverride == nil ? "" : " preview"
            weatherStatusMenuItem?.title = "Weather: \(temperature)°C · \(condition.label)\(preview)"
            statusItem?.button?.title = "🌾 \(temperature)°"
        } else if let weatherOverride {
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
        if period ?? currentFarmPeriod != displayedFarmPeriod { beginFarmTransition() }
        farmPeriodOverride = period
        farmArtwork = farmImage(displayedFarmPeriod)
        markSelected(sender)
        clearRareFarmEventIfNeeded()
        maybeStartRareFarmEvent()
        updateFarmAnimation()
        updateFarmImage()
    }

    @objc private func selectWeather(_ sender: NSMenuItem) {
        let previous = displayedWeather?.condition
        let weather = (sender.representedObject as? String).flatMap(WeatherCondition.init(rawValue:))
        if weather ?? currentWeather?.condition != previous { beginFarmTransition() }
        weatherOverride = weather
        markSelected(sender)
        handleWeatherTransition(from: previous, to: displayedWeather?.condition)
        maybeStartRareFarmEvent()
        updateFarmAnimation()
        updateFarmImage()
        updateFarmMetadata()
        if weatherOverride == nil { requestWeatherAccessIfNeeded() }
    }

    @objc private func selectFarmLife(_ sender: NSMenuItem) {
        farmLifeOverride = sender.tag == -1 ? nil : sender.tag == 1
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
            let result = Result { try CodexUsage.fetch() }
            DispatchQueue.main.async { self?.apply(result) }
        }
    }

    @objc private func cardTapped() {
        guard !isRefreshing else { return }
        let image = usageButton?.image ?? usageImage(nil)
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
        let period = farmPeriod(at: Calendar.current.component(.hour, from: Date()))
        guard period != currentFarmPeriod else { return }
        if farmPeriodOverride == nil { beginFarmTransition() }
        currentFarmPeriod = period
        guard farmPeriodOverride == nil else { return }
        farmArtwork = farmImage(period)
        clearRareFarmEventIfNeeded()
        maybeStartRareFarmEvent()
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
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,weather_code,precipitation,rain,showers,snowfall,cloud_cover,is_day"
            ),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { return }
        isFetchingWeather = true
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result = Result<WeatherState, Error> {
                if let error { throw error }
                guard
                    let response = response as? HTTPURLResponse,
                    response.statusCode == 200,
                    let data
                else { throw URLError(.badServerResponse) }
                return try parseWeather(data)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingWeather = false
                switch result {
                case .success(let weather):
                    let previous = self.displayedWeather?.condition
                    self.beginFarmTransition()
                    self.currentWeather = weather
                    if self.weatherOverride == nil {
                        self.handleWeatherTransition(from: previous, to: weather.condition)
                    } else {
                        self.clearRareFarmEventIfNeeded()
                    }
                    self.maybeStartRareFarmEvent()
                    self.updateFarmAnimation()
                    self.updateFarmImage()
                    self.updateFarmMetadata()
                case .failure(let error):
                    NSLog("Codex Touch Bar weather failed: %@", error.localizedDescription)
                }
            }
        }.resume()
    }

    private func updateFarmAnimation() {
        let weatherIsAnimated = displayedWeather?.condition.isAnimated == true
        let lifeIsAnimated = isFarmLifeVisible
        guard weatherIsAnimated || lifeIsAnimated || rareFarmEvent != nil || farmTransitionImage != nil else {
            farmAnimationTimer?.invalidate()
            farmAnimationTimer = nil
            return
        }
        guard farmAnimationTimer == nil else { return }
        let timer = Timer(timeInterval: animationFrame, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            self.weatherPhase = (self.weatherPhase + 0.002).truncatingRemainder(dividingBy: 1)
            self.advanceClouds()
            self.advanceFarmLife()
            self.advanceRareFarmEvent()
            self.advanceFarmTransition()
            self.updateFarmImage()
        }
        RunLoop.main.add(timer, forMode: .common)
        farmAnimationTimer = timer
    }

    private func beginFarmTransition() {
        guard farmButton != nil else { return }
        let size = NSSize(width: farmWidth, height: 30)
        let snapshot = NSImage(size: size)
        snapshot.lockFocus()
        farmFrameImage().draw(in: NSRect(origin: .zero, size: size))
        snapshot.unlockFocus()
        farmTransitionImage = snapshot
        farmTransitionProgress = 0
        updateFarmAnimation()
    }

    private func advanceFarmTransition() {
        guard farmTransitionImage != nil else { return }
        farmTransitionProgress += CGFloat(animationFrame / 0.8)
        guard farmTransitionProgress >= 1 else { return }
        farmTransitionImage = nil
        farmTransitionProgress = 1
        updateFarmAnimation()
    }

    private func maybeStartRareFarmEvent() {
        guard rareFarmEvent == nil else { return }
        let event: RareFarmEvent?
        switch displayedFarmPeriod {
        case .dusk where Int.random(in: 0..<2) == 0:
            event = .fireflies
        case .night where Int.random(in: 0..<3) == 0:
            event = .shootingStar
        default:
            event = nil
        }
        guard let event else { return }
        startRareFarmEvent(event)
    }

    private func startRareFarmEvent(_ event: RareFarmEvent) {
        guard rareFarmEventIsAllowed(
            event,
            period: displayedFarmPeriod,
            weather: displayedWeather?.condition
        ) else { return }
        rareFarmEvent = event
        rareFarmEventPhase = 0
        updateFarmAnimation()
        updateFarmImage()
    }

    private func advanceRareFarmEvent() {
        guard let rareFarmEvent else { return }
        let duration: TimeInterval
        switch rareFarmEvent {
        case .rainbow: duration = 20
        case .fireflies: duration = 10
        case .shootingStar: duration = 1.2
        }
        rareFarmEventPhase += CGFloat(animationFrame / duration)
        guard rareFarmEventPhase >= 1 else { return }
        self.rareFarmEvent = nil
        rareFarmEventPhase = 0
        updateFarmAnimation()
    }

    private func handleWeatherTransition(
        from previous: WeatherCondition?,
        to current: WeatherCondition?
    ) {
        if let current, shouldShowRainbow(
            from: previous,
            to: current,
            period: displayedFarmPeriod
        ) {
            startRareFarmEvent(.rainbow)
        } else {
            clearRareFarmEventIfNeeded()
        }
    }

    private func clearRareFarmEventIfNeeded() {
        guard let rareFarmEvent, !rareFarmEventIsAllowed(
            rareFarmEvent,
            period: displayedFarmPeriod,
            weather: displayedWeather?.condition
        ) else { return }
        self.rareFarmEvent = nil
        rareFarmEventPhase = 0
    }

    private func advanceClouds() {
        guard [.cloudy, .rain, .thunderstorm].contains(displayedWeather?.condition) else {
            return
        }
        for index in cloudPhases.indices {
            let phase = cloudPhases[index]
            let next = wrappedOffset(phase + cloudSpeeds[index] / 3, width: 1)
            cloudPhases[index] = next
            if next < phase { cloudSpeeds[index] = CGFloat.random(in: 0.0012...0.003) }
        }
    }

    private func advanceFarmLife() {
        guard isFarmLifeVisible else { return }
        let speedRanges: [ClosedRange<CGFloat>] = [
            0.0055...0.009, 0.0025...0.0045, 0.0035...0.006
        ]
        for index in animalPhases.indices {
            let phase = animalPhases[index]
            var pauseFor: Int?
            if animalPauseTicks[index] == 0 && phase > 0.05 && phase < 0.95 {
                if Int.random(in: 0..<900) == 0 {
                    animalMovingLeft[index].toggle()
                    animalSpeeds[index] = CGFloat.random(in: speedRanges[index])
                    pauseFor = Int.random(in: 15...36)
                } else if Int.random(in: 0..<540) == 0 {
                    pauseFor = Int.random(in: 30...75)
                }
            }
            let step = nextAnimalStep(
                phase: phase,
                pauseTicks: animalPauseTicks[index],
                movingLeft: animalMovingLeft[index],
                pauseFor: pauseFor,
                speed: animalSpeeds[index] / 3
            )
            animalPhases[index] = step.phase
            animalPauseTicks[index] = step.pauseTicks
            let wrapped = animalMovingLeft[index] ? step.phase > phase : step.phase < phase
            if wrapped { animalSpeeds[index] = CGFloat.random(in: speedRanges[index]) }
        }
    }

    private func updateFarmImage() {
        farmButton?.image = farmFrameImage()
    }

    private func updateFarmMetadata() {
        defer { updateMenuBar() }
        if let currentWeather, let displayedWeather {
            let temperature = Int(currentWeather.temperature.rounded())
            farmButton?.toolTip = "\(temperature)°C · \(displayedWeather.condition.label). Farm life roams in fair daylight. Weather data by Open-Meteo.com."
            farmButton?.setAccessibilityValue("\(temperature) degrees Celsius, \(displayedWeather.condition.label)")
        } else if let weatherOverride {
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
                usageButton?.image = usageImage(usage)
                isRefreshing = false
            }
            usageButton?.toolTip = "\(usage.remainingPercent)% Codex usage remaining. Tap to refresh."
            usageButton?.setAccessibilityValue("\(usage.remainingPercent) percent remaining")
        case .failure(let error):
            usageButton?.image = feedbackImage(
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
        usageButton?.image = usageImage(usage, remainingPercentages: percentages)
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
            usageButton?.image = usageImage(usage)
            isRefreshing = false
            return
        }
        let strength = CGFloat(sin(Double(phase) * .pi))
        usageButton?.image = usageImage(usage, sparkle: strength)
        DispatchQueue.main.asyncAfter(deadline: .now() + animationFrame) { [weak self] in
            self?.animateSparkle(usage, phase: phase + 1.0 / 10.0)
        }
    }

    private func animateRefresh(_ image: NSImage, phase: CGFloat = 0) {
        guard isRefreshing, tappedRefresh else { return }
        if let currentUsage {
            usageButton?.image = usageImage(currentUsage, cometPhase: phase)
        } else {
            usageButton?.image = feedbackImage(
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

    private func feedbackImage(
        _ image: NSImage?,
        text: String,
        color: NSColor,
        shimmer: CGFloat? = nil
    ) -> NSImage {
        NSImage(size: NSSize(width: cardWidth, height: 30), flipped: false) { rect in
            image?.draw(in: rect)
            let cardRect = rect
            NSColor(white: 0.02, alpha: 0.88).setFill()
            NSBezierPath(roundedRect: cardRect, xRadius: 6, yRadius: 6).fill()
            if let shimmer {
                let width: CGFloat = 76
                let band = NSRect(
                    x: -width + (self.cardWidth + width) * shimmer,
                    y: 0,
                    width: width,
                    height: rect.height
                )
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: cardRect, xRadius: 6, yRadius: 6).addClip()
                NSGradient(colors: [
                    .clear,
                    NSColor.white.withAlphaComponent(0.22),
                    .clear
                ])?.draw(in: band, angle: 0)
                NSGraphicsContext.restoreGraphicsState()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 13, weight: .bold)
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: (self.cardWidth - size.width) / 2, y: (rect.height - size.height) / 2),
                withAttributes: attributes
            )
            return true
        }
    }

    private func farmImage(_ period: FarmPeriod) -> NSImage {
        let size = NSSize(width: farmTileWidth, height: 30)
        guard
            let url = Bundle.main.url(
                forResource: "farm-\(period.rawValue)",
                withExtension: "png"
            ),
            let image = NSImage(contentsOf: url)
        else {
            NSLog("Missing farm asset for %@", period.rawValue)
            return NSImage(size: size)
        }
        image.size = size
        return image
    }

    private func farmFrameImage() -> NSImage {
        let size = NSSize(width: farmWidth, height: 30)
        return NSImage(size: size, flipped: false) { rect in
            for x in stride(from: 0, to: self.farmWidth, by: self.farmTileWidth) {
                self.farmArtwork.draw(
                    in: NSRect(x: x, y: 0, width: self.farmTileWidth, height: rect.height)
                )
            }
            if let weather = self.displayedWeather {
                self.drawWeather(weather, in: rect)
            }
            if let event = self.rareFarmEvent {
                self.drawRareFarmEvent(event, in: rect)
            }
            if self.isFarmLifeVisible {
                self.drawRoamingFarmLife(in: rect)
            }
            if let weather = self.currentWeather {
                self.drawTemperature(weather.temperature, in: rect)
            }
            if let transition = self.farmTransitionImage {
                transition.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1 - easedProgress(self.farmTransitionProgress)
                )
            }
            return true
        }
    }

    private func drawRareFarmEvent(_ event: RareFarmEvent, in rect: NSRect) {
        switch event {
        case .rainbow:
            let alpha = min(1, min(rareFarmEventPhase * 5, (1 - rareFarmEventPhase) * 5))
            let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue]
            for (index, color) in colors.enumerated() {
                let path = NSBezierPath()
                path.lineWidth = 1.3
                path.appendArc(
                    withCenter: NSPoint(x: rect.midX + 35, y: 2),
                    radius: 14 - CGFloat(index) * 1.8,
                    startAngle: 0,
                    endAngle: 180
                )
                color.withAlphaComponent(alpha * 0.78).setStroke()
                path.stroke()
            }
        case .fireflies:
            for index in 0..<8 {
                let pulse = (sin(Double(rareFarmEventPhase * .pi * 20 + CGFloat(index))) + 1) / 2
                let x = wrappedOffset(
                    CGFloat((index * 47 + 31) % 320) + CGFloat(sin(Double(rareFarmEventPhase * .pi * 4 + CGFloat(index)))) * 6,
                    width: rect.width
                )
                let y = CGFloat(5 + (index * 7) % 14)
                    + CGFloat(cos(Double(rareFarmEventPhase * .pi * 6 + CGFloat(index)))) * 2
                NSColor(calibratedRed: 1, green: 0.86, blue: 0.18, alpha: pulse * 0.2)
                    .setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 2, y: y - 2, width: 4, height: 4)).fill()
                NSColor(calibratedRed: 1, green: 0.96, blue: 0.45, alpha: pulse * 0.95)
                    .setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)).fill()
            }
        case .shootingStar:
            let alpha = sin(rareFarmEventPhase * .pi)
            let x = -10 + (rect.width + 30) * rareFarmEventPhase
            let y = rect.height - 3 - rareFarmEventPhase * 12
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.move(to: NSPoint(x: x - 16, y: y + 5))
            path.line(to: NSPoint(x: x, y: y))
            NSColor(calibratedRed: 0.72, green: 0.88, blue: 1, alpha: alpha * 0.75)
                .setStroke()
            path.stroke()
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
        }
    }

    private func drawRoamingFarmLife(in rect: NSRect) {
        let animals: [(index: Int, width: CGFloat)] = [(0, 18), (1, 24), (2, 22)]
        let originalMovingLeft = [false, true, true]
        for (index, animal) in animals.enumerated() {
            let phase = animalPhases[index]
            let x = -animal.width + (rect.width + animal.width) * phase
            drawFarmSprite(
                animal.index,
                in: NSRect(x: x, y: 0, width: animal.width, height: 18),
                flippedHorizontally: animalMovingLeft[index] != originalMovingLeft[index]
            )
        }
        let tractorWidth: CGFloat = 34
        let tractorPhase = wrappedOffset(weatherPhase + 0.76, width: 1)
        let tractorX = -tractorWidth + (rect.width + tractorWidth) * tractorPhase
        drawFarmSprite(4, in: NSRect(x: tractorX, y: 0, width: tractorWidth, height: 18))
    }

    private func drawWeather(_ weather: WeatherState, in rect: NSRect) {
        switch weather.condition {
        case .clear:
            break
        case .cloudy:
            NSColor.black.withAlphaComponent(min(0.24, 0.08 + weather.cloudCover / 600)).setFill()
            rect.fill()
            drawClouds(in: rect, fraction: 0.95)
        case .fog:
            NSColor(calibratedWhite: 0.72, alpha: 0.3).setFill()
            rect.fill()
            for index in 0..<6 {
                let width: CGFloat = index.isMultiple(of: 2) ? 150 : 110
                let x = wrappedOffset(
                    weatherPhase * rect.width + CGFloat(index) * 83,
                    width: rect.width + width
                ) - width / 2
                NSColor.white.withAlphaComponent(0.24).setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: CGFloat(2 + index % 4 * 7), width: width, height: 4),
                    xRadius: 2,
                    yRadius: 2
                ).fill()
            }
        case .rain:
            NSColor.black.withAlphaComponent(0.3).setFill()
            rect.fill()
            drawClouds(in: rect, fraction: 0.9)
            drawRain(in: rect, count: 44, speed: 10)
        case .snow:
            NSColor.black.withAlphaComponent(0.22).setFill()
            rect.fill()
            drawClouds(in: rect, fraction: 0.75)
            drawSnow(in: rect, count: 32, speed: 3)
        case .thunderstorm:
            NSColor.black.withAlphaComponent(0.42).setFill()
            rect.fill()
            drawClouds(in: rect, fraction: 0.95)
            drawRain(in: rect, count: 58, speed: 13)
            let flashPhase = wrappedOffset(weatherPhase * 3, width: 1)
            if flashPhase > 0.94 {
                let strength = sin((flashPhase - 0.94) / 0.06 * .pi) * 0.42
                NSColor.white.withAlphaComponent(strength).setFill()
                rect.fill()
            }
        }
    }

    private func drawClouds(in rect: NSRect, fraction: CGFloat) {
        let clouds: [(width: CGFloat, height: CGFloat, y: CGFloat, alpha: CGFloat)] = [
            (20, 10, 19, 1), (14, 7, 22, 0.8),
            (18, 9, 15, 0.9), (12, 6, 18, 0.7)
        ]
        for (index, cloud) in clouds.enumerated() {
            let x = -cloud.width + (rect.width + cloud.width) * cloudPhases[index]
            drawCloud(
                in: NSRect(x: x, y: cloud.y, width: cloud.width, height: cloud.height),
                fraction: fraction * cloud.alpha
            )
        }
    }

    private func drawCloud(in rect: NSRect, fraction: CGFloat) {
        guard let cloud = cloudImage(for: displayedFarmPeriod) else { return }
        cloud.draw(
            in: rect,
            from: NSRect.zero,
            operation: NSCompositingOperation.sourceOver,
            fraction: fraction
        )
    }

    private func cloudImage(for period: FarmPeriod) -> NSImage? {
        if let cloud = cloudArtworkByPeriod[period.rawValue] { return cloud }
        guard let farmSprites else { return nil }
        let size = NSSize(width: 320, height: 197)
        let cloud = NSImage(size: size)
        cloud.lockFocus()
        farmSprites.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(x: 1345, y: 257, width: 320, height: 197),
            operation: .sourceOver,
            fraction: 1
        )
        cloudTint(for: period).setFill()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        cloud.unlockFocus()
        cloudArtworkByPeriod[period.rawValue] = cloud
        return cloud
    }

    private func drawRain(in rect: NSRect, count: Int, speed: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = 0.9
        for index in 0..<count {
            let progress = wrappedOffset(
                weatherPhase * speed + CGFloat(index) * 0.113,
                width: 1
            )
            let x = wrappedOffset(CGFloat((index * 47) % 360) - progress * 12, width: rect.width)
            let y = rect.height - progress * (rect.height + 9)
            path.move(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x - 3, y: y - 7))
        }
        NSColor(calibratedRed: 0.72, green: 0.88, blue: 1, alpha: 0.82).setStroke()
        path.stroke()
    }

    private func drawSnow(in rect: NSRect, count: Int, speed: CGFloat) {
        NSColor.white.withAlphaComponent(0.94).setFill()
        for index in 0..<count {
            let flakeSpeed = speed + CGFloat(index % 3) - 1
            let offset = CGFloat((index * 37) % count) / CGFloat(count)
            let progress = wrappedOffset(
                weatherPhase * flakeSpeed + offset,
                width: 1
            )
            let turns = CGFloat(1 + index % 3)
            let amplitude = CGFloat(3 + index % 5)
            let drift = CGFloat(sin(Double(progress * .pi * 2 * turns + CGFloat(index)))) * amplitude
                + CGFloat(sin(Double(weatherPhase * .pi * 6 + CGFloat(index) * 0.41))) * 1.5
            let x = wrappedOffset(CGFloat((index * 83) % 360) + drift, width: rect.width)
            let y = rect.height - progress * (rect.height + 4)
            let diameter: CGFloat = index.isMultiple(of: 3) ? 2 : 1.4
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: diameter, height: diameter)).fill()
        }
    }

    private func drawTemperature(_ temperature: Double, in rect: NSRect) {
        let text = "\(Int(temperature.rounded()))°"
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = .zero
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold),
            .shadow: shadow
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.maxX - size.width - 4, y: 18), withAttributes: attributes)
    }

    private func drawFarmSprite(
        _ index: Int,
        in rect: NSRect,
        fraction: CGFloat = 1,
        flippedHorizontally: Bool = false
    ) {
        guard let farmSprites, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if flippedHorizontally {
            context.translateBy(x: rect.midX * 2, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        let cellWidth = farmSprites.size.width / 5
        farmSprites.draw(
            in: rect,
            from: NSRect(x: cellWidth * CGFloat(index), y: 150, width: cellWidth, height: 420),
            operation: .sourceOver,
            fraction: fraction
        )
    }

    private func usageImage(
        _ usage: Usage?,
        remainingPercentages: [CGFloat]? = nil,
        sparkle: CGFloat = 0,
        cometPhase: CGFloat? = nil
    ) -> NSImage {
        let size = NSSize(width: cardWidth, height: 30)
        return NSImage(size: size, flipped: false) { rect in
            let cardRect = rect
            let background = NSBezierPath(
                roundedRect: cardRect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: 6,
                yRadius: 6
            )
            NSColor(white: 0.035, alpha: 1).setFill()
            background.fill()

            let iconRect = NSRect(x: 2, y: 2, width: 26, height: 26)
            if let codexIcon = self.codexIcon {
                codexIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
                if sparkle > 0 {
                    codexIcon.draw(
                        in: iconRect,
                        from: .zero,
                        operation: .screen,
                        fraction: sparkle * 0.8
                    )
                    "✦".draw(at: NSPoint(x: 24, y: 19), withAttributes: [
                        .foregroundColor: NSColor.white.withAlphaComponent(sparkle),
                        .font: NSFont.systemFont(ofSize: 8, weight: .bold)
                    ])
                }
            } else {
                ">_".draw(at: NSPoint(x: 5, y: 8), withAttributes: [
                    .foregroundColor: NSColor.systemBlue,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
                ])
            }

            "Codex".draw(at: NSPoint(x: 34, y: 16), withAttributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .bold)
            ])
            let liveColor: NSColor = usage == nil ? .systemGray : .systemGreen
            NSGraphicsContext.saveGraphicsState()
            let liveGlow = NSShadow()
            liveGlow.shadowColor = liveColor.withAlphaComponent(0.9)
            liveGlow.shadowBlurRadius = 3
            liveGlow.shadowOffset = .zero
            liveGlow.set()
            liveColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 34, y: 7, width: 4, height: 4)).fill()
            NSGraphicsContext.restoreGraphicsState()
            (usage?.detailLabel ?? "Loading…").draw(at: NSPoint(x: 41, y: 3), withAttributes: [
                .foregroundColor: NSColor(white: 0.72, alpha: 1),
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold)
            ])

            for index in 0..<2 {
                let window = usage?.windows.indices.contains(index) == true ? usage?.windows[index] : nil
                let y: CGFloat = index == 0 ? 17 : 4
                let barY: CGFloat = index == 0 ? 20 : 7
                let remaining = remainingPercentages.flatMap {
                    $0.indices.contains(index) ? $0[index] : nil
                } ?? window.map { CGFloat($0.remainingPercent) }
                let color: NSColor = remaining.map {
                    $0 > 50 ? .systemGreen : $0 > 20 ? .systemOrange : .systemRed
                } ?? .systemGray
                let label = window?.label ?? (index == 0 ? "5h" : "Wk")
                label.draw(at: NSPoint(x: 110, y: y), withAttributes: [
                    .foregroundColor: NSColor(white: 0.72, alpha: 1),
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
                ])

                let track = NSRect(x: 130, y: barY, width: 70, height: 4)
                NSColor(white: 0.45, alpha: 0.6).setFill()
                NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
                if let remaining, remaining > 0 {
                    let fill = NSRect(
                        x: track.minX,
                        y: track.minY,
                        width: track.width * remaining / 100,
                        height: track.height
                    )
                    NSGraphicsContext.saveGraphicsState()
                    let shadow = NSShadow()
                    shadow.shadowColor = color.withAlphaComponent(0.9)
                    shadow.shadowBlurRadius = 3
                    shadow.shadowOffset = .zero
                    shadow.set()
                    color.setFill()
                    NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill()
                    NSGraphicsContext.restoreGraphicsState()

                    if let cometPhase {
                        let offset = cometOffset(width: fill.width, phase: cometPhase)
                        let headX = fill.minX + offset
                        let strength = CGFloat(sin(Double(cometPhase) * .pi))
                        let tailWidth = min(18, offset)
                        if tailWidth > 0 {
                            let tail = NSRect(
                                x: headX - tailWidth,
                                y: track.minY - 1,
                                width: tailWidth,
                                height: track.height + 2
                            )
                            NSGradient(colors: [
                                .clear,
                                color.withAlphaComponent(strength * 0.65),
                                NSColor.white.withAlphaComponent(strength)
                            ])?.draw(in: tail, angle: 0)
                        }
                        NSGraphicsContext.saveGraphicsState()
                        let cometGlow = NSShadow()
                        cometGlow.shadowColor = color.withAlphaComponent(strength)
                        cometGlow.shadowBlurRadius = 6
                        cometGlow.shadowOffset = .zero
                        cometGlow.set()
                        NSColor.white.withAlphaComponent(strength).setFill()
                        NSBezierPath(ovalIn: NSRect(
                            x: headX - 2,
                            y: track.midY - 2,
                            width: 4,
                            height: 4
                        )).fill()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }

                (remaining.map { "\(Int($0.rounded()))%" } ?? "—").draw(at: NSPoint(x: 205, y: y), withAttributes: [
                    .foregroundColor: color,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
                ])
                self.resetText(window?.resetsAt).draw(at: NSPoint(x: 240, y: y), withAttributes: [
                    .foregroundColor: NSColor(white: 0.72, alpha: 1),
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
                ])
            }
            return true
        }
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }
}

func runSelfTest() {
    precondition(
        Usage(windows: [], model: "gpt-5.6-sol", planType: "team").detailLabel == "5.6-Sol · Team"
    )
    precondition(cometOffset(width: 70, phase: 0.5) == 35)
    precondition(cometOffset(width: 70, phase: 2) == 70)
    precondition(wrappedOffset(-10, width: 360) == 350)
    precondition(wrappedOffset(370, width: 360) == 10)
    let pausedAnimal = nextAnimalStep(phase: 0.5, pauseTicks: 2, movingLeft: false, pauseFor: nil)
    precondition(pausedAnimal.phase == 0.5 && pausedAnimal.pauseTicks == 1)
    let stoppingAnimal = nextAnimalStep(phase: 0.5, pauseTicks: 0, movingLeft: false, pauseFor: 15)
    precondition(stoppingAnimal.phase == 0.5 && stoppingAnimal.pauseTicks == 15)
    precondition(nextAnimalStep(phase: 0.5, pauseTicks: 0, movingLeft: false, pauseFor: nil).phase > 0.5)
    precondition(nextAnimalStep(phase: 0.5, pauseTicks: 0, movingLeft: true, pauseFor: nil).phase < 0.5)
    let slowAnimal = nextAnimalStep(phase: 0.5, pauseTicks: 0, movingLeft: false, pauseFor: nil, speed: 0.002)
    let fastAnimal = nextAnimalStep(phase: 0.5, pauseTicks: 0, movingLeft: false, pauseFor: nil, speed: 0.008)
    precondition(fastAnimal.phase > slowAnimal.phase)
    precondition(nextAnimalStep(phase: 0.999, pauseTicks: 0, movingLeft: false, pauseFor: nil, speed: 0.008).phase < 0.999)
    precondition(farmPeriod(at: 6) == .dawn)
    precondition(farmPeriod(at: 12) == .day)
    precondition(farmPeriod(at: 18) == .dusk)
    precondition(farmPeriod(at: 23) == .night)
    precondition(cloudTint(for: .day).alphaComponent == 0)
    precondition(cloudTint(for: .night).alphaComponent > cloudTint(for: .dusk).alphaComponent)
    precondition(weatherCondition(for: 0) == .clear)
    precondition(weatherCondition(for: 2) == .cloudy)
    precondition(weatherCondition(for: 45) == .fog)
    precondition(weatherCondition(for: 63) == .rain)
    precondition(weatherCondition(for: 75) == .snow)
    precondition(weatherCondition(for: 95) == .thunderstorm)
    precondition(rareFarmEventIsAllowed(.rainbow, period: .day, weather: .clear))
    precondition(!rareFarmEventIsAllowed(.rainbow, period: .night, weather: .clear))
    precondition(rareFarmEventIsAllowed(.fireflies, period: .dusk, weather: .cloudy))
    precondition(!rareFarmEventIsAllowed(.fireflies, period: .dusk, weather: .rain))
    precondition(rareFarmEventIsAllowed(.shootingStar, period: .night, weather: nil))
    precondition(shouldShowRainbow(from: .rain, to: .clear, period: .day))
    precondition(!shouldShowRainbow(from: .clear, to: .cloudy, period: .day))
    precondition(farmLifeIsVisible(period: .dawn, weather: nil))
    precondition(farmLifeIsVisible(period: .day, weather: .cloudy))
    precondition(!farmLifeIsVisible(period: .dusk, weather: .clear))
    precondition(!farmLifeIsVisible(period: .night, weather: .clear))
    precondition(!farmLifeIsVisible(period: .day, weather: .rain))
    precondition(interpolatedPercentage(from: 80, to: 60, progress: 0.5) == 70)
    precondition(interpolatedPercentage(from: 80, to: 60, progress: 2) == 60)
    precondition(easedProgress(-1) == 0)
    precondition(easedProgress(0.5) == 0.5)
    precondition(easedProgress(2) == 1)
    precondition(codexGlyphAlpha(brightness: 0.28, chroma: 0.004) == 0)
    precondition(codexGlyphAlpha(brightness: 0.98, chroma: 0) == 1)
    precondition(codexGlyphAlpha(brightness: 0.98, chroma: 0.44) == 1)
    let pixel = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1,
        pixelsHigh: 1,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 4,
        bitsPerPixel: 32
    )!
    pixel.setColor(NSColor(deviceRed: 0.28, green: 0.28, blue: 0.28, alpha: 0), atX: 0, y: 0)
    precondition(pixel.colorAt(x: 0, y: 0)?.alphaComponent == 0)

    let response = """
    {"id":1,"result":{}}
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":15},"secondary":{"usedPercent":42}},"rateLimitsByLimitId":null}}
    """
    let usage = try! CodexUsage.parse(Data(response.utf8))
    precondition(usage.remainingPercent == 58)

    let clamped = """
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":109}}}}
    """
    precondition(try! CodexUsage.parse(Data(clamped.utf8)).remainingPercent == 0)

    let weatherResponse = """
    {"current":{"temperature_2m":29.6,"weather_code":63,"precipitation":1.2,"snowfall":0,"cloud_cover":88,"is_day":1}}
    """
    let weather = try! parseWeather(Data(weatherResponse.utf8))
    precondition(weather.condition == .rain)
    precondition(weather.temperature == 29.6)
    precondition(weather.cloudCover == 88)
    precondition(weather.isDay)
    print("Self-test passed")
}

switch CommandLine.arguments.dropFirst().first {
case "--self-test":
    runSelfTest()
case "--status":
    do {
        let usage = try CodexUsage.fetch()
        print("Codex \(usage.remainingPercent)% remaining · \(usage.detailLabel)")
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
default:
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
