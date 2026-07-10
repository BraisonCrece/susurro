// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Susurro",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Susurro",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Susurro",
            linkerSettings: [
                // Sparkle.framework is embedded into Contents/Frameworks at packaging time (build-app.sh)
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "SusurroTests",
            dependencies: ["Susurro"],
            path: "Tests/SusurroTests"
        )
    ]
)
