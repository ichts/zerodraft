// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FirstLine",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "FirstLine", targets: ["FirstLine"]),
    ],
    targets: [
        .executableTarget(
            name: "FirstLine",
            path: "Sources/FirstLine",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
            ]
        ),
        .testTarget(
            name: "FirstLineTests",
            dependencies: ["FirstLine"],
            path: "Tests/FirstLineTests"
        )
    ]
)
