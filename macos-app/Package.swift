// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoltaAutoUpdate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VoltaAutoUpdate", targets: ["VoltaAutoUpdate"])
    ],
    targets: [
        .executableTarget(
            name: "VoltaAutoUpdate",
            path: "Sources/VoltaAutoUpdate"
        )
    ],
    swiftLanguageModes: [.v5]
)
