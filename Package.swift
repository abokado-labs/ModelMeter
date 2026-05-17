// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageTracker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexUsageTracker", targets: ["CodexUsageTracker"])
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageTracker",
            path: "Sources/CodexUsageTracker",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
