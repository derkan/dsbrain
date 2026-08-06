// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DSBrain",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DSBrain", targets: ["DSBrain"]),
        .executable(name: "smc-helper", targets: ["smc-helper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "SMCKit",
            path: "DSBrain/SMCKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        // Library so tests can `@testable import` without a public API surface.
        .target(
            name: "DSBrainLib",
            dependencies: [
                "SMCKit",
                .product(name: "Yams", package: "Yams"),
            ],
            path: "DSBrain",
            exclude: [
                "AppEntry.swift",
                "Assets.xcassets",
                "Info.plist",
                "AppIcon.icns",
                "SMCKit",
                "Helper",
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "DSBrain",
            dependencies: ["DSBrainLib"],
            path: "DSBrain",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "AppIcon.icns",
                "SMCKit",
                "Helper",
                "Config",
                "Server",
                "Views",
                "Utilities",
                "HostingViewController.swift",
                "AppDelegate.swift",
            ],
            sources: ["AppEntry.swift"]
        ),
        .executableTarget(
            name: "smc-helper",
            dependencies: ["SMCKit"],
            path: "DSBrain/Helper",
            sources: ["main.swift"],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "DSBrainTests",
            dependencies: ["DSBrainLib"],
            path: "Tests/DSBrainTests"
        ),
    ]
)
