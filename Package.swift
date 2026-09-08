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
                // Name the vendored archives by full path rather than
                // -L + -l. A search-path lookup takes the first match and
                // prefers a .dylib over a .a, so an environment that exports
                // LIBRARY_PATH (Homebrew setups commonly add /opt/homebrew/lib)
                // links a system-wide FreeTDS instead of the archive in this
                // repo, silently and with no diagnostic. A full path leaves
                // the linker nothing to search.
                .unsafeFlags([
                    "\(Context.packageDirectory)/Sources/CFreeTDS/libsybdb.a",
                    "\(Context.packageDirectory)/Sources/CFreeTDS/libssl.a",
                    "\(Context.packageDirectory)/Sources/CFreeTDS/libcrypto.a",
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
