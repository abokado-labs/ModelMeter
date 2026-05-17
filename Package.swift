// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ModelMeter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ModelMeter", targets: ["ModelMeter"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "ModelMeter",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ModelMeter",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "ModelMeterTests",
            dependencies: ["ModelMeter"],
            path: "Tests/ModelMeterTests"
        )
    ]
)
