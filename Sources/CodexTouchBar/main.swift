import AppKit
import Darwin
import Foundation

switch CommandLine.arguments.dropFirst().first {
case "--self-test":
    runSelfTest()
case "--status":
    do {
        let usage = try CodexUsageClient().fetch()
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
