// swift-tools-version: 6.0
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
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0")
    ],
    targets: [
        .systemLibrary(
            name: "FreeTDS",
            pkgConfig: "freetds",
            providers: [
                .brew(["freetds"])
            ]
        ),
        .target(
            name: "CFreeTDS",
            dependencies: ["FreeTDS"],
            path: "Sources/CFreeTDS",
            publicHeadersPath: "include"
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
        .testTarget(
            name: "FreeTDSKitIntegrationTests",
            dependencies: ["FreeTDSKit"],
            resources: [.copy("db-setup.sql"), .copy("docker-compose.yml"),.copy("run-integration-tests.sh")])
    ]
)
