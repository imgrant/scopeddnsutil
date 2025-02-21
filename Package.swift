// swift-tools-version:5.8

import PackageDescription

let package = Package(
    name: "scopeddnsutil",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "scopeddnsutil",
            targets: ["scopeddnsutil"]
        )
    ],
    targets: [
        .executableTarget(
            name: "scopeddnsutil",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        )
    ]
)