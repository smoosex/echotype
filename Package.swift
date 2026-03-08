// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "echotype",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "1.9.4"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "0.16.0"),
        .package(url: "https://github.com/soniqo/speech-swift.git", exact: "0.0.3"),
    ],
    targets: [
        .executableTarget(
            name: "echotype",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                "WhisperKit",
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "Sources/stt",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
