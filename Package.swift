// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LLMUsageTracker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LLMUsageTracker", targets: ["LLMUsageTracker"])
    ],
    targets: [
        .executableTarget(
            name: "LLMUsageTracker",
            path: "Sources/LLMUsageTracker",
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
