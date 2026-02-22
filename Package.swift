// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Clipster",
    platforms: [
        .macOS("15.0") // Using macOS 15 for modern SwiftUI toolbar APIs.
    ],
    products: [
        .executable(name: "Clipster", targets: ["Clipster"])
    ],
    dependencies: [
        // Dependencies can be added here later.
    ],
    targets: [
        .executableTarget(
            name: "Clipster",
            dependencies: [],
            exclude: ["Resources/Info.plist"],
            resources: [
                // Only process the asset catalog
                .process("Resources/AppIcon.xcassets")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Clipster/Resources/Info.plist"
                ])
            ]
        )
    ]
)
