// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeTDSKit",
    platforms: [
        .macOS(.v14,)
    ],
    products: [
        .library(
            name: "FreeTDSKit",
            targets: ["FreeTDSKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0")
    ],
    targets: [
        .target(
                    name: "CFreeTDS",
                    path: "Sources/CFreeTDS",
                    publicHeadersPath: "include",
                    cSettings: [
                        .headerSearchPath("include")
                    ],
                    linkerSettings: [
                        .unsafeFlags(["-L.", "-lsybdb"])
                    ]
                ),
        .target(
            name: "FreeTDSKit",
            dependencies: [
                "CFreeTDS",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "FreeTDSKitTests",
            dependencies: ["FreeTDSKit"]
        ),
        // Integration tests (requires Docker and a live SQL Server instance)
        .testTarget(
            name: "FreeTDSKitIntegrationTests",
            dependencies: ["FreeTDSKit"],
            resources: [.copy("db-setup.sql"), .copy("docker-compose.yml"), .copy("run-integration-tests.sh")]
        ),
    ]
)
