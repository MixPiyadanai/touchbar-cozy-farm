import AppKit

final class UsageRenderer {
    static let detailRect = NSRect(x: 41, y: 1, width: 67, height: 12)

    private let width: CGFloat
    private lazy var codexIcon = Self.loadCodexIcon()

    init(width: CGFloat) {
        self.width = width
    }

    static func compactDetail(_ detail: String, maxWidth: CGFloat, font: NSFont) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        guard
            (detail as NSString).size(withAttributes: attributes).width > maxWidth,
            let separator = detail.range(of: " · ")
        else { return detail }
        return String(detail[..<separator.lowerBound])
    }

    static func glyphAlpha(brightness: CGFloat, chroma: CGFloat) -> CGFloat {
        let blue = (chroma - 0.05) / 0.15
        let white = (brightness - 0.72) / 0.18
        return min(1, max(0, max(blue, white)))
    }

    static func cometOffset(width: CGFloat, phase: CGFloat) -> CGFloat {
        width * min(1, max(0, phase))
    }

    func image(
        _ usage: Usage?,
        remainingPercentages: [CGFloat]? = nil,
        sparkle: CGFloat = 0,
        cometPhase: CGFloat? = nil
    ) -> NSImage {
        let size = NSSize(width: width, height: 30)
        return NSImage(size: size, flipped: false) { [self] rect in
            let background = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: 6,
                yRadius: 6
            )
            NSColor(white: 0.035, alpha: 1).setFill()
            background.fill()

            let iconRect = NSRect(x: 2, y: 2, width: 26, height: 26)
            if let codexIcon {
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

            let detailFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
            let detailStyle = NSMutableParagraphStyle()
            detailStyle.lineBreakMode = .byTruncatingTail
            let detail = Self.compactDetail(
                usage?.detailLabel ?? "Loading…",
                maxWidth: Self.detailRect.width,
                font: detailFont
            )
            (detail as NSString).draw(with: Self.detailRect, options: [
                .usesLineFragmentOrigin,
                .truncatesLastVisibleLine
            ], attributes: [
                .foregroundColor: NSColor(white: 0.72, alpha: 1),
                .font: detailFont,
                .paragraphStyle: detailStyle
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
                        let offset = Self.cometOffset(width: fill.width, phase: cometPhase)
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

                (remaining.map { "\(Int($0.rounded()))%" } ?? "—").draw(
                    at: NSPoint(x: 205, y: y),
                    withAttributes: [
                        .foregroundColor: color,
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
                    ]
                )
                resetText(window?.resetsAt).draw(at: NSPoint(x: 240, y: y), withAttributes: [
                    .foregroundColor: NSColor(white: 0.72, alpha: 1),
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
                ])
            }
            return true
        }
    }

    func feedbackImage(
        _ image: NSImage?,
        text: String,
        color: NSColor,
        shimmer: CGFloat? = nil
    ) -> NSImage {
        NSImage(size: NSSize(width: width, height: 30), flipped: false) { [self] rect in
            image?.draw(in: rect)
            NSColor(white: 0.02, alpha: 0.88).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            if let shimmer {
                let bandWidth: CGFloat = 76
                let band = NSRect(
                    x: -bandWidth + (width + bandWidth) * shimmer,
                    y: 0,
                    width: bandWidth,
                    height: rect.height
                )
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
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
                at: NSPoint(x: (width - size.width) / 2, y: (rect.height - size.height) / 2),
                withAttributes: attributes
            )
            return true
        }
    }

    private static func loadCodexIcon() -> NSImage? {
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
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
                let chroma = brightness - min(color.redComponent, color.greenComponent, color.blueComponent)
                let alpha = color.alphaComponent * glyphAlpha(brightness: brightness, chroma: chroma)
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
