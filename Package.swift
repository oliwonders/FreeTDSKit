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
        // FreeTDS and the OpenSSL it links, as one static universal archive.
        // Built by Support/buildandlinkfreetds.sh. A binary target rather
        // than linker flags because SwiftPM rejects unsafeFlags in any
        // package consumed as a dependency.
        .binaryTarget(
            name: "FreeTDS",
            path: "Frameworks/FreeTDS.xcframework"
        ),
        .target(
            name: "CFreeTDS",
            dependencies: ["FreeTDS"],
            path: "Sources/CFreeTDS",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("iconv")
            ]
        ),
        .target(
            name: "FreeTDSKit",
            dependencies: [
                "CFreeTDS",
            ],
            // Declares the required-reason APIs that FreeTDS and OpenSSL call
            // (stat and friends: the file-timestamp category). They are linked
            // statically, so the calls end up in the app's own binary.
            resources: [
                .copy("PrivacyInfo.xcprivacy")
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
