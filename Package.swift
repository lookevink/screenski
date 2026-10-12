// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "screenski",
    platforms: [.macOS(.v14)],
    targets: [
        // Declarations for the private macOS APIs screenski relies on
        // (CGVirtualDisplay for virtual screens, IOAVService for DDC/CI).
        .target(
            name: "CPrivateDisplay",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreDisplay"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(name: "screenski", dependencies: ["CPrivateDisplay"]),
    ]
)
