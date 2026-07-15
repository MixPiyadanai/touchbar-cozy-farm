// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TouchBarCozyFarm",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexTouchBar", targets: ["CodexTouchBar"])
    ],
    targets: [
        .executableTarget(
            name: "CodexTouchBar",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("MapKit")
            ]
        )
    ]
)
