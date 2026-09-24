// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "WriteItDown",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "WriteItDown", targets: ["WriteItDown"]),
    ],
    targets: [
        .executableTarget(
            name: "WriteItDown",
            path: "Sources/FirstLine",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
            ],
            resources: [
                // Bundled writing fonts and SIL Open Font License texts.
                // Processed into Bundle.module so registration resolves them by name.
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "WriteItDownTests",
            dependencies: ["WriteItDown"],
            path: "Tests/FirstLineTests"
        )
    ]
)
