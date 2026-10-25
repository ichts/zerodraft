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
    dependencies: [
        // Pinned exactly: the binary target is fetched as a ZIP whose checksum
        // Sparkle's own manifest pins, so the pin keeps the payload auditable.
        // Bump deliberately, with the release-Mac end-to-end proof.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "WriteItDown",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/FirstLine",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
            ],
            resources: [
                // Bundled writing fonts and SIL Open Font License texts.
                // Processed into Bundle.module so registration resolves them by name.
                .process("Resources"),
            ],
            linkerSettings: [
                // The app bundle keeps Sparkle.framework in Contents/Frameworks.
                // Without this rpath the binary only resolves it beside the build product.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "WriteItDownTests",
            dependencies: ["WriteItDown"],
            path: "Tests/FirstLineTests"
        )
    ]
)
