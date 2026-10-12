// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NanoNeo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NeoKit", targets: ["NeoKit"]),
        .executable(name: "nanoneo", targets: ["nanoneo"]),
    ],
    targets: [
        // USB mode switching, the Neo's protocol, and the inbox sync flow.
        .target(
            name: "NeoKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOUSBHost"),
            ]
        ),

        // The menu bar app. `make bundle` wraps this binary in NanoNeo.app.
        .executableTarget(name: "NanoNeoApp", dependencies: ["NeoKit"]),

        // Developer CLI for exercising NeoKit against real hardware.
        .executableTarget(name: "nanoneo", dependencies: ["NeoKit"]),

        .testTarget(name: "NeoKitTests", dependencies: ["NeoKit"]),
    ],
    swiftLanguageModes: [.v5]
)
