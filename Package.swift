// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FreeTDSKit",
    platforms: [
        .macOS(.v13)
       ],
    products: [
        .library(
            name: "FreeTDSKit",
            targets: ["FreeTDSKit"])
    ],
    dependencies: [
            .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3")  // Add this line
        ],
    targets: [
        .target(
                    name: "CFreeTDS",
                    dependencies: ["FreeTDS"],
                    path: "Sources/CFreeTDS",
                    publicHeadersPath: "include",
                    cSettings: [
                        .headerSearchPath("opt/homebrew/include")
                    ],
                    linkerSettings: [
                        .linkedLibrary("sybdb") // Links the FreeTDS library
                    ]
                ),
        .target(
            name: "FreeTDSKit",
            dependencies: ["CFreeTDS",
                .product(name: "Logging", package: "swift-log")]
        ),
        .testTarget(
            name: "FreeTDSKitTests",
            dependencies: ["FreeTDSKit"]
        ),
        .systemLibrary(
            name: "FreeTDS",
            providers: [
                .brew(["freetds"])
        ])
    ]
)
