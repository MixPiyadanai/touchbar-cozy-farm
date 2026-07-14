import AppKit
import Foundation

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

final class FarmScene {
    private let width: CGFloat
    private let tileWidth: CGFloat
    private let frameDuration: TimeInterval
    private var currentPeriod: FarmPeriod
    private lazy var artwork = farmImage(currentPeriod)
    private lazy var sprites: NSImage? = {
        guard let url = resourceBundle.url(forResource: "farm-sprites", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
    private var cloudArtworkByPeriod: [String: NSImage] = [:]
    private var periodOverride: FarmPeriod?
    private var lifeOverride: Bool?
    private var weatherPhase: CGFloat = 0
    private var cloudPhases: [CGFloat] = [0, 0.24, 0.51, 0.78]
    private var cloudSpeeds: [CGFloat] = [0.0025, 0.0015, 0.002, 0.0018]
    private var animalPhases: [CGFloat] = [0, 0.28, 0.54]
    private var animalSpeeds: [CGFloat] = [0.008, 0.0035, 0.005]
    private var animalPauseTicks = [0, 0, 0]
    private var animalMovingLeft = [false, true, true]
    private var rareEvent: RareFarmEvent?
    private var rareEventPhase: CGFloat = 0
    private var transitionImage: NSImage?
    private var transitionProgress: CGFloat = 1

    private(set) var currentWeather: WeatherState?
    private(set) var weatherOverride: WeatherCondition?

    var displayedPeriod: FarmPeriod {
        periodOverride ?? currentPeriod
    }

    var displayedWeather: WeatherState? {
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

    var requiresAnimation: Bool {
        displayedWeather?.condition.isAnimated == true
            || isLifeVisible
            || rareEvent != nil
            || transitionImage != nil
    }

    private var isLifeVisible: Bool {
        lifeOverride ?? farmLifeIsVisible(
            period: displayedPeriod,
            weather: displayedWeather?.condition
        )
    }

    init(
        width: CGFloat,
        tileWidth: CGFloat,
        frameDuration: TimeInterval,
        date: Date = Date()
    ) {
        self.width = width
        self.tileWidth = tileWidth
        self.frameDuration = frameDuration
        currentPeriod = farmPeriod(at: Calendar.current.component(.hour, from: date))
    }

    func setPeriodOverride(_ period: FarmPeriod?) {
        if period ?? currentPeriod != displayedPeriod { beginTransition() }
        periodOverride = period
        artwork = farmImage(displayedPeriod)
        clearRareEventIfNeeded()
        _ = maybeStartRareEvent()
    }

    func setWeatherOverride(_ weather: WeatherCondition?) {
        let previous = displayedWeather?.condition
        if weather ?? currentWeather?.condition != previous { beginTransition() }
        weatherOverride = weather
        handleWeatherTransition(from: previous, to: displayedWeather?.condition)
        _ = maybeStartRareEvent()
    }

    func setLifeOverride(_ showLife: Bool?) {
        lifeOverride = showLife
    }

    @discardableResult
    func updateClock(date: Date = Date()) -> Bool {
        let period = farmPeriod(at: Calendar.current.component(.hour, from: date))
        guard period != currentPeriod else { return false }
        if periodOverride == nil { beginTransition() }
        currentPeriod = period
        guard periodOverride == nil else { return false }
        artwork = farmImage(period)
        clearRareEventIfNeeded()
        _ = maybeStartRareEvent()
        return true
    }

    func applyWeather(_ weather: WeatherState) {
        let previous = displayedWeather?.condition
        beginTransition()
        currentWeather = weather
        if weatherOverride == nil {
            handleWeatherTransition(from: previous, to: weather.condition)
        } else {
            clearRareEventIfNeeded()
        }
        _ = maybeStartRareEvent()
    }

    @discardableResult
    func maybeStartRareEvent() -> Bool {
        guard rareEvent == nil else { return false }
        let event: RareFarmEvent?
        switch displayedPeriod {
        case .dusk where Int.random(in: 0..<2) == 0:
            event = .fireflies
        case .night where Int.random(in: 0..<3) == 0:
            event = .shootingStar
        default:
            event = nil
        }
        guard let event else { return false }
        return startRareEvent(event)
    }

    func advance() {
        weatherPhase = (weatherPhase + 0.002).truncatingRemainder(dividingBy: 1)
        advanceClouds()
        advanceFarmLife()
        advanceRareEvent()
        advanceTransition()
    }

    func frameImage() -> NSImage {
        let size = NSSize(width: width, height: 30)
        return NSImage(size: size, flipped: false) { [self] rect in
            for x in stride(from: 0, to: width, by: tileWidth) {
                artwork.draw(in: NSRect(x: x, y: 0, width: tileWidth, height: rect.height))
            }
            if let weather = displayedWeather {
                drawWeather(weather, in: rect)
            }
            if let rareEvent {
                drawRareEvent(rareEvent, in: rect)
            }
            if isLifeVisible {
                drawRoamingFarmLife(in: rect)
            }
            if let currentWeather {
                drawTemperature(currentWeather.temperature, in: rect)
            }
            if let transitionImage {
                transitionImage.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1 - easedProgress(transitionProgress)
                )
            }
            return true
        }
    }

    private func beginTransition() {
        let size = NSSize(width: width, height: 30)
        let snapshot = NSImage(size: size)
        snapshot.lockFocus()
        frameImage().draw(in: NSRect(origin: .zero, size: size))
        snapshot.unlockFocus()
        transitionImage = snapshot
        transitionProgress = 0
    }

    private func advanceTransition() {
        guard transitionImage != nil else { return }
        transitionProgress += CGFloat(frameDuration / 0.8)
        guard transitionProgress >= 1 else { return }
        transitionImage = nil
        transitionProgress = 1
    }

    private func startRareEvent(_ event: RareFarmEvent) -> Bool {
        guard rareFarmEventIsAllowed(
            event,
            period: displayedPeriod,
            weather: displayedWeather?.condition
        ) else { return false }
        rareEvent = event
        rareEventPhase = 0
        return true
    }

    private func advanceRareEvent() {
        guard let rareEvent else { return }
        let duration: TimeInterval
        switch rareEvent {
        case .rainbow: duration = 20
        case .fireflies: duration = 10
        case .shootingStar: duration = 1.2
        }
        rareEventPhase += CGFloat(frameDuration / duration)
        guard rareEventPhase >= 1 else { return }
        self.rareEvent = nil
        rareEventPhase = 0
    }

    private func handleWeatherTransition(
        from previous: WeatherCondition?,
        to current: WeatherCondition?
    ) {
        if let current, shouldShowRainbow(
            from: previous,
            to: current,
            period: displayedPeriod
        ) {
            _ = startRareEvent(.rainbow)
        } else {
            clearRareEventIfNeeded()
        }
    }

    private func clearRareEventIfNeeded() {
        guard let rareEvent, !rareFarmEventIsAllowed(
            rareEvent,
            period: displayedPeriod,
            weather: displayedWeather?.condition
        ) else { return }
        self.rareEvent = nil
        rareEventPhase = 0
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
        guard isLifeVisible else { return }
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

    private func farmImage(_ period: FarmPeriod) -> NSImage {
        let size = NSSize(width: tileWidth, height: 30)
        guard
            let url = resourceBundle.url(
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

    private func drawRareEvent(_ event: RareFarmEvent, in rect: NSRect) {
        switch event {
        case .rainbow:
            let alpha = min(1, min(rareEventPhase * 5, (1 - rareEventPhase) * 5))
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
                let pulse = (sin(Double(rareEventPhase * .pi * 20 + CGFloat(index))) + 1) / 2
                let x = wrappedOffset(
                    CGFloat((index * 47 + 31) % 320)
                        + CGFloat(sin(Double(rareEventPhase * .pi * 4 + CGFloat(index)))) * 6,
                    width: rect.width
                )
                let y = CGFloat(5 + (index * 7) % 14)
                    + CGFloat(cos(Double(rareEventPhase * .pi * 6 + CGFloat(index)))) * 2
                NSColor(calibratedRed: 1, green: 0.86, blue: 0.18, alpha: pulse * 0.2)
                    .setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 2, y: y - 2, width: 4, height: 4)).fill()
                NSColor(calibratedRed: 1, green: 0.96, blue: 0.45, alpha: pulse * 0.95)
                    .setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)).fill()
            }
        case .shootingStar:
            let alpha = sin(rareEventPhase * .pi)
            let x = -10 + (rect.width + 30) * rareEventPhase
            let y = rect.height - 3 - rareEventPhase * 12
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
                let fogWidth: CGFloat = index.isMultiple(of: 2) ? 150 : 110
                let x = wrappedOffset(
                    weatherPhase * rect.width + CGFloat(index) * 83,
                    width: rect.width + fogWidth
                ) - fogWidth / 2
                NSColor.white.withAlphaComponent(0.24).setFill()
                NSBezierPath(
                    roundedRect: NSRect(
                        x: x,
                        y: CGFloat(2 + index % 4 * 7),
                        width: fogWidth,
                        height: 4
                    ),
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
        guard let cloud = cloudImage(for: displayedPeriod) else { return }
        cloud.draw(in: rect, from: .zero, operation: .sourceOver, fraction: fraction)
    }

    private func cloudImage(for period: FarmPeriod) -> NSImage? {
        if let cloud = cloudArtworkByPeriod[period.rawValue] { return cloud }
        guard let sprites else { return nil }
        let size = NSSize(width: 320, height: 197)
        let cloud = NSImage(size: size)
        cloud.lockFocus()
        sprites.draw(
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
            let progress = wrappedOffset(weatherPhase * flakeSpeed + offset, width: 1)
            let turns = CGFloat(1 + index % 3)
            let amplitude = CGFloat(3 + index % 5)
            let drift = CGFloat(
                sin(Double(progress * .pi * 2 * turns + CGFloat(index)))
            ) * amplitude + CGFloat(
                sin(Double(weatherPhase * .pi * 6 + CGFloat(index) * 0.41))
            ) * 1.5
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
        guard let sprites, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if flippedHorizontally {
            context.translateBy(x: rect.midX * 2, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        let cellWidth = sprites.size.width / 5
        sprites.draw(
            in: rect,
            from: NSRect(x: cellWidth * CGFloat(index), y: 150, width: cellWidth, height: 420),
            operation: .sourceOver,
            fraction: fraction
        )
    }

}
