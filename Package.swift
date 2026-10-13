// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AltTabWindowSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AltTabWindowSwitcher", targets: ["AltTabWindowSwitcher"])
    ],
    targets: [
        .executableTarget(
            name: "AltTabWindowSwitcher",
            path: "Sources/AltTab"
        )
    ],
    swiftLanguageVersions: [.v5]
)
