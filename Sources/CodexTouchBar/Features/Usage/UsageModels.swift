import CoreGraphics
import Foundation

func interpolatedPercentage(from: Int, to: Int, progress: CGFloat) -> CGFloat {
    let progress = min(1, max(0, progress))
    let eased = progress * progress * (3 - 2 * progress)
    return CGFloat(from) + CGFloat(to - from) * eased
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
