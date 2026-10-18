// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "JVoice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "JVoice",
            targets: ["JVoice"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/WhisperKit.git",
            exact: "1.0.0"
        ),
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts.git",
            exact: "1.10.0"
        ),
        // Auto-updates (docs/sparkle-updates/README.md). Exact pin: the bundled framework,
        // the release tools in ~/Developer/Sparkle/2.10.0 and the appcast format must agree.
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.10.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "JVoice",
            dependencies: [
                .product(
                    name: "WhisperKit",
                    package: "WhisperKit"
                ),
                .product(
                    name: "KeyboardShortcuts",
                    package: "KeyboardShortcuts"
                ),
                .product(
                    name: "Sparkle",
                    package: "Sparkle"
                )
            ],
            // Sparkle.framework is embedded in JVoice.app/Contents/Frameworks by
            // scripts/build-app.sh, so the executable looks for it there.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "JVoiceTests",
            dependencies: ["JVoice"]
        )
    ]
)
