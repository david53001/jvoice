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
                )
            ]
        ),
        .testTarget(
            name: "JVoiceTests",
            dependencies: ["JVoice"]
        )
    ]
)
