// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-uninstaller",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Uninstaller", targets: ["Uninstaller"]),
        .library(name: "UninstallerCore", targets: ["UninstallerCore"]),
    ],
    targets: [
        .target(name: "UninstallerCore"),
        .executableTarget(
            name: "Uninstaller",
            dependencies: ["UninstallerCore"]
        ),
        // Standalone assertion runner for the correctness-critical core. Runs under
        // plain CommandLineTools (no XCTest/swift-testing). `swift run corecheck`.
        .executableTarget(
            name: "corecheck",
            dependencies: ["UninstallerCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
