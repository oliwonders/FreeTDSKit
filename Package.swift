// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FreeTDSKit",
    platforms: [
        .macOS(.v15, )
    ],
    products: [
        .library(
            name: "FreeTDSKit",
            targets: ["FreeTDSKit"]
        )
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
                .unsafeFlags([
                    "-L\(Context.packageDirectory)/Sources/CFreeTDS",
                    "-lsybdb",
                    "-lssl",
                    "-lcrypto",
                    "-liconv",
                ])
            ]
        ),
        .target(
            name: "FreeTDSKit",
            dependencies: [
                "CFreeTDS",
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
            resources: [
                .copy("db-setup.sql"), .copy("docker-compose.yml"),
                .copy("run-integration-tests.sh"),
            ]
        ),
    ]
)
