import CoreGraphics
import Foundation

func easedProgress(_ progress: CGFloat) -> CGFloat {
    let progress = min(1, max(0, progress))
    return progress * progress * (3 - 2 * progress)
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
