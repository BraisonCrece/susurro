// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Susurro",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Susurro",
            path: "Sources/Susurro"
        )
    ]
)
