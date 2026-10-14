// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lumo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Lumo", targets: ["Lumo"])
    ],
    dependencies: [
        // Future: Sparkle for auto-update (M8, behind flag)
    ],
    targets: [
        .executableTarget(
            name: "Lumo",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("Resources"),
                .process("UI/Shaders/LumoShaders.metal")
            ],
            swiftSettings: [
                .define("DIRECT_DISTRIBUTION"),
                .define("ENABLE_MEDIA_REMOTE", .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("MediaPlayer"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "LumoNativeHost",
            dependencies: [],
            path: "BrowserExtension",
            exclude: [
                "background.js",
                "content.js",
                "manifest.json",
                "com.lumo.native.json",
                "install-native-host.sh"
            ],
            sources: ["NativeHost.swift"],
            swiftSettings: [
                .define("ENABLE_MEDIA_REMOTE", .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "LumoTests",
            dependencies: ["Lumo"],
            path: "Tests"
        )
    ]
)
