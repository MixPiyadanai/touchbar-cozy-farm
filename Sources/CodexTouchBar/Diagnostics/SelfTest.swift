import AppKit
import Foundation

func runSelfTest() {
#if SWIFT_PACKAGE
    precondition(resourceBundle.url(forResource: "farm-day", withExtension: "png") != nil)
#endif
    runUsageSelfTests()
    runFarmSelfTests()
    print("Self-test passed")
}

private func runUsageSelfTests() {
    precondition(
        Usage(windows: [], model: "gpt-5.6-sol", planType: "team").detailLabel
            == "5.6-Sol · Team"
    )
    precondition(UsageRenderer.cometOffset(width: 70, phase: 0.5) == 35)
    precondition(UsageRenderer.cometOffset(width: 70, phase: 2) == 70)
    precondition(interpolatedPercentage(from: 80, to: 60, progress: 0.5) == 70)
    precondition(interpolatedPercentage(from: 80, to: 60, progress: 2) == 60)

    let detailFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    precondition(UsageRenderer.detailRect.maxX < 110)
    precondition(
        UsageRenderer.compactDetail(
            "5.6-Sol · Team",
            maxWidth: UsageRenderer.detailRect.width,
            font: detailFont
        ) == "5.6-Sol · Team"
    )
    precondition(
        UsageRenderer.compactDetail(
            "5.6-Terra · Teamwork",
            maxWidth: UsageRenderer.detailRect.width,
            font: detailFont
        ) == "5.6-Terra"
    )
    precondition(UsageRenderer.glyphAlpha(brightness: 0.28, chroma: 0.004) == 0)
    precondition(UsageRenderer.glyphAlpha(brightness: 0.98, chroma: 0) == 1)
    precondition(UsageRenderer.glyphAlpha(brightness: 0.98, chroma: 0.44) == 1)

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
    pixel.setColor(
        NSColor(deviceRed: 0.28, green: 0.28, blue: 0.28, alpha: 0),
        atX: 0,
        y: 0
    )
    precondition(pixel.colorAt(x: 0, y: 0)?.alphaComponent == 0)

    let response = """
    {"id":1,"result":{}}
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":15},"secondary":{"usedPercent":42}},"rateLimitsByLimitId":null}}
    """
    let usage = try! CodexUsageClient.parse(Data(response.utf8))
    precondition(usage.remainingPercent == 58)

    let clamped = """
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":109}}}}
    """
    precondition(try! CodexUsageClient.parse(Data(clamped.utf8)).remainingPercent == 0)
}

private func runFarmSelfTests() {
    precondition(wrappedOffset(-10, width: 360) == 350)
    precondition(wrappedOffset(370, width: 360) == 10)
    let pausedAnimal = nextAnimalStep(
        phase: 0.5,
        pauseTicks: 2,
        movingLeft: false,
        pauseFor: nil
    )
    precondition(pausedAnimal.phase == 0.5 && pausedAnimal.pauseTicks == 1)
    let stoppingAnimal = nextAnimalStep(
        phase: 0.5,
        pauseTicks: 0,
        movingLeft: false,
        pauseFor: 15
    )
    precondition(stoppingAnimal.phase == 0.5 && stoppingAnimal.pauseTicks == 15)
    precondition(
        nextAnimalStep(
            phase: 0.5,
            pauseTicks: 0,
            movingLeft: false,
            pauseFor: nil
        ).phase > 0.5
    )
    precondition(
        nextAnimalStep(
            phase: 0.5,
            pauseTicks: 0,
            movingLeft: true,
            pauseFor: nil
        ).phase < 0.5
    )
    let slowAnimal = nextAnimalStep(
        phase: 0.5,
        pauseTicks: 0,
        movingLeft: false,
        pauseFor: nil,
        speed: 0.002
    )
    let fastAnimal = nextAnimalStep(
        phase: 0.5,
        pauseTicks: 0,
        movingLeft: false,
        pauseFor: nil,
        speed: 0.008
    )
    precondition(fastAnimal.phase > slowAnimal.phase)
    precondition(
        nextAnimalStep(
            phase: 0.999,
            pauseTicks: 0,
            movingLeft: false,
            pauseFor: nil,
            speed: 0.008
        ).phase < 0.999
    )

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
    precondition(easedProgress(-1) == 0)
    precondition(easedProgress(0.5) == 0.5)
    precondition(easedProgress(2) == 1)

    let weatherResponse = """
    {"current":{"temperature_2m":29.6,"weather_code":63,"precipitation":1.2,"snowfall":0,"cloud_cover":88,"is_day":1}}
    """
    let weather = try! WeatherClient.parse(Data(weatherResponse.utf8))
    precondition(weather.condition == .rain)
    precondition(weather.temperature == 29.6)
    precondition(weather.cloudCover == 88)
    precondition(weather.isDay)
}
