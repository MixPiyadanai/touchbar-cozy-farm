import Foundation

struct CodexUsageClient {
    func fetch() throws -> Usage {
        guard let executable = Self.codexExecutable() else { throw UsageError.codexNotFound }

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
        _ = try Self.readResponse(id: 1, from: output.fileHandleForReading)

        let rateLimits = """
        {"method":"initialized"}
        {"method":"account/rateLimits/read","id":2}

        """
        input.fileHandleForWriting.write(Data(rateLimits.utf8))
        let data = try Self.readResponse(id: 2, from: output.fileHandleForReading)

        let config = """
        {"method":"config/read","id":3,"params":{"includeLayers":false}}

        """
        input.fileHandleForWriting.write(Data(config.utf8))
        let configData = try? Self.readResponse(id: 3, from: output.fileHandleForReading)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UsageError.appServerFailed(process.terminationStatus)
        }
        return try Self.parse(data, configData: configData)
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
