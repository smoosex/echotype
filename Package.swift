// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "echotype",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "1.9.4"),
    ],
    targets: [
        .executableTarget(
            name: "echotype",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/stt",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
