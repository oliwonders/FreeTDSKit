# FreeTDSKit

FreeTDSKit is a Swift wrapper around the [FreeTDS](https://github.com/FreeTDS/freetds) DB-Library client, exposing a Swift-native API for connecting to Microsoft SQL Server and executing queries without pushing C types into the public interface.

**Platforms:** macOS 15+ (arm64, x86_64) and iOS / iPadOS 17+ (devices, and the Simulator on Apple silicon and Intel Macs).

> The package is still evolving, but the current layout is intentionally simple: SwiftPM builds a small C shim, links a vendored dynamic XCFramework, and exposes the result through a Swift actor-based API.

## What Is In The Repo

- `Sources/FreeTDSKit`: Swift API surface, including `TDSConnection`, `SQLResult`, and type mapping.
- `Sources/CFreeTDS`: the C shim (`FreeTDSWrapper.c` / `.h`).
- `Sources/FreeTDSKit/AppleRootCertificates.pem`: Apple's root certificates, which server certificates are checked against on iOS (see [Encryption and certificate checks](#encryption-and-certificate-checks)).
- `Frameworks/FreeTDS.xcframework`: `FreeTDS.framework`, a dynamic framework holding FreeTDS with OpenSSL linked in, and the FreeTDS headers, for macOS (arm64 + x86_64), iOS (arm64) and the iOS Simulator (arm64 + x86_64).
- `Support/buildandlinkfreetds.sh`: rebuilds OpenSSL and FreeTDS from source for every platform and architecture and regenerates the XCFramework.
- `Support/export-apple-roots.sh`: regenerates `AppleRootCertificates.pem` from this Mac's system root store; the build script runs it.
- `Support/generate_freetds_pc.sh`: generates a Homebrew `freetds.pc` file and symlink for local tooling/Xcode header discovery.
- `Tests/FreeTDSKitTests`: fast unit tests.
- `Tests/FreeTDSKitIntegrationTests`: Docker-backed SQL Server integration tests.

## How Linking Works

This package does not expect users to install FreeTDS separately. FreeTDS 1.5.19 (with FreeTDSKit's patches, see `Support/patches`) and OpenSSL 3.5.9 are linked into one dynamic framework, `FreeTDS.framework`, shipped as `Frameworks/FreeTDS.xcframework`. The framework also carries the FreeTDS headers (`#include <FreeTDS/sybdb.h>`), a `FreeTDS` module map, an Info.plist and a privacy manifest.

The XCFramework has one slice per platform:

| Slice | Architectures | Minimum OS | Bundle layout | Install name |
| --- | --- | --- | --- | --- |
| `macos-arm64_x86_64` | arm64, x86_64 | macOS 15.0 | versioned | `@rpath/FreeTDS.framework/Versions/A/FreeTDS` |
| `ios-arm64` | arm64 | iOS 17.0 | shallow | `@rpath/FreeTDS.framework/FreeTDS` |
| `ios-arm64_x86_64-simulator` | arm64, x86_64 | iOS 17.0 | shallow | `@rpath/FreeTDS.framework/FreeTDS` |

**Why dynamic.** FreeTDS is licensed under the LGPL, which lets a closed-source app use it as long as users can replace the library with their own build. As a separate framework inside the app (`Contents/Frameworks/FreeTDS.framework` on macOS, `Frameworks/FreeTDS.framework` on iOS), it can be; linked statically, every app would have to offer its object files for relinking instead. iOS gets the same dynamic framework for the same reason. OpenSSL (Apache 2.0) has no such condition and is linked into the framework statically, so the two always travel together. Xcode embeds and re-signs the framework in any app that uses FreeTDSKit; there is nothing to set up. (Xcode's iOS app templates already set `LD_RUNPATH_SEARCH_PATHS` to `@executable_path/Frameworks`, which is where the framework is found.)

**Versioned and shallow bundles.** macOS frameworks use the versioned layout: everything lives in `Versions/A`, reached through `Versions/Current` and top-level symlinks, with the Info.plist and privacy manifest in `Resources/`. iOS frameworks must be shallow: the library, `Info.plist`, `PrivacyInfo.xcprivacy`, `Headers/` and `Modules/` sit at the top of the bundle, with no `Versions/` and no symlinks, and the install name has no `Versions/A`. The iOS Info.plist carries `MinimumOSVersion`, `UIDeviceFamily` (iPhone and iPad) and `CFBundleSupportedPlatforms` (`iPhoneOS` or `iPhoneSimulator`) where the macOS one carries `LSMinimumSystemVersion` and `MacOSX`.

`Package.swift` declares it as a binary target, and the `CFreeTDS` shim depends on it:

```swift
.binaryTarget(name: "FreeTDS", path: "Frameworks/FreeTDS.xcframework"),
.target(
    name: "CFreeTDS",
    dependencies: ["FreeTDS"],
    path: "Sources/CFreeTDS",
    publicHeadersPath: "include",
    linkerSettings: [.linkedLibrary("iconv")]
),
```

Two reasons it is a binary target rather than linker flags:

- **SwiftPM rejects `unsafeFlags` in any package that is not the root package.** An app that added FreeTDSKit from GitHub failed to resolve while the manifest linked the archives by path.
- **Nothing is left for the linker to search for.** With `-L` plus `-lsybdb`, the linker takes the first match on its search path and prefers a `.dylib` over a `.a`. An environment that exports `LIBRARY_PATH` (Homebrew setups commonly add `/opt/homebrew/lib`) would silently link a system-wide FreeTDS. The binary target hands the linker the framework directly. For the same reason the module map has no `link` directive.

To check what a build actually linked, `otool -L` on the app's binary should list `@rpath/FreeTDS.framework/Versions/A/FreeTDS` (macOS) or `@rpath/FreeTDS.framework/FreeTDS` (iOS) and no `libsybdb`, `libssl` or `libcrypto`, and `FreeTDSKit.versions` should report the versions vendored here.

The framework is self-contained, so the package is suitable for sandboxed, Mac App Store and iOS App Store apps, including a universal purchase that shares code between the two. Such an app still needs the `com.apple.security.network.client` entitlement to reach SQL Server, and it cannot read `/usr/local/etc/freetds.conf` or `~/.freetds.conf` from inside the sandbox.

## App Store Notes

- **Privacy manifest.** FreeTDS and OpenSSL call `stat`, `fstat` and `lstat`, which Apple lists as required-reason APIs (file timestamps). `FreeTDS.framework` carries a `PrivacyInfo.xcprivacy` declaring reason `C617.1`, as Apple asks of third-party SDKs, and FreeTDSKit's resource bundle declares the same.
- **Signed XCFramework.** `Frameworks/FreeTDS.xcframework` and the framework inside it are signed with a Developer ID Application certificate; `codesign -dvv Frameworks/FreeTDS.xcframework` shows by whom. The build script signs both when `FREETDSKIT_CODESIGN_IDENTITY` is set. A rebuilt framework is unsigned until then, so sign before tagging a release. Apps re-sign the embedded framework with their own identity.
- **Sandbox.** Needs the outgoing network connections entitlement (`com.apple.security.network.client`). The macOS root certificates are exported to the app container's caches folder, so no other file access is required.
- **iOS.** iOS apps need no entitlement for outgoing connections. The iOS slices are shallow frameworks with `CFBundlePackageType` `FMWK`, `CFBundleExecutable`, a numeric `CFBundleShortVersionString`, `MinimumOSVersion` matching the library's deployment target, and `UIDeviceFamily`, which is what App Store validation looks for in an embedded framework. The device slice holds arm64 only; simulator code lives in its own slice, so nothing has to be stripped before upload. FreeTDS's `freetds.conf` lookups find nothing on iOS, which FreeTDSKit doesn't rely on.

## Client Usage

First add FreeTDSKit to your application in Xcode or run this:

```bash
swift package add https://github.com/oliwonders/FreeTDSKit.git
```

```swift
import FreeTDSKit

let config = ConnectionConfiguration(
    host: "your_server",
    port: 1438,
    username: "your_user",
    password: "your_password",
    database: "your_database"
)

let connection = try TDSConnection(configuration: config)

let result = try await connection.execute(queryString: "SELECT id, name FROM users")
print(result.rows)

struct User: Decodable {
    let id: Int
    let name: String
}

for try await user in connection.query(queryString: "SELECT id, name FROM users", as: User.self) {
    print(user)
}

await connection.close()
```

### Encryption and certificate checks

Connections are encrypted and the server's certificate is verified by default,
against the system root certificates. A server with a publicly trusted
certificate, such as Azure SQL, needs nothing extra.

OpenSSL can't read Apple's trust store, so FreeTDSKit hands it a PEM file of
roots. On macOS that file is exported from the live trust store at launch. iOS
has no API that lists the trusted roots, so there FreeTDSKit uses
`AppleRootCertificates.pem`, a snapshot of the same Apple root program taken
when the package was built (`Support/export-apple-roots.sh`). The snapshot only
changes with a FreeTDSKit release, and neither file carries the extra
restrictions Apple applies to some roots, or certificates added by a
configuration profile; use `certificateAuthorityFile` for a company CA on iOS.

| Setting | Default | What it does |
| --- | --- | --- |
| `encryption` | `.mandatory` | `.mandatory` refuses to connect unless the whole session is encrypted. `.strict` is TDS 8.0, TLS from the first byte (SQL Server 2022 and Azure SQL). `.optional` falls back to clear text when the server can't do TLS; avoid it outside isolated networks. |
| `trustServerCertificate` | `false` | Skips the certificate check, like Microsoft's `TrustServerCertificate=yes`. For development servers with self-signed certificates only. Ignored with `.strict`. |
| `certificateAuthorityFile` | `nil` | A PEM file of CAs to trust instead of the system roots: a company CA, or a server's own self-signed certificate. |
| `hostNameInCertificate` | `nil` | The name the certificate must match, when it differs from `host`, e.g. when connecting by IP address. |

```swift
// A local SQL Server in Docker, which generates its own certificate:
var config = ConnectionConfiguration(host: "localhost", username: "sa", password: pw, database: "dev")
config.trustServerCertificate = true
```

Earlier versions of FreeTDSKit only *requested* encryption and never checked the
certificate, so a server without TLS, or anyone between client and server, got
the login and the data. A server that previously connected without these
settings may now need `trustServerCertificate` or `certificateAuthorityFile`.

### Spatial values

`geography` and `geometry` columns come back as `.spatial`, holding WKT in the form `STAsText()` produces (`POINT (-122.35 47.65)`: longitude first for geography). They don't need `.STAsText()` in the query, so it doesn't matter how the value was produced: a plain column, a computed value such as `SpatialPoint.STBuffer(50)`, any arm of a `UNION`, a CTE or a stored procedure all work.

SQL Server sends these values in its own binary format ([MS-SSCLRT]), which `SQLServerSpatial.wkt(fromSerialized:)` decodes. Points, line strings, polygons (with holes), their multi- forms and geometry collections are supported. Curves (`CIRCULARSTRING`, `COMPOUNDCURVE`, `CURVEPOLYGON`) and `FULLGLOBE` come back as `.binary`, as do other user-defined types such as `hierarchyid`. Z and M values are dropped.

The bytes don't say whether a value is geography (latitude stored first) or geometry (x first). A value is read as geography when it has an SRID and every stored first coordinate is a valid latitude. A `geometry` value with an SRID whose x values all fall within ±90 would be read with its axes swapped; give such columns `.STAsText()` in the query.

[MS-SSCLRT]: https://learn.microsoft.com/openspecs/sql_server_protocols/ms-ssclrt/

### Errors

`TDSConnectionError` carries the messages SQL Server sent for the failure, oldest
first. That order matters: a single failure often produces several messages, with
the specific cause first and a generic summary after it, so `primaryMessage` is
the one that explains what actually went wrong.

```swift
do {
    let connection = try TDSConnection(configuration: config)
} catch let error as TDSConnectionError {
    print(error)
    // Connection failed: Msg 4060, Level 11, State 2, Line 1: Cannot open database
    // "demo" requested by the login. The login failed. | Msg 18456, Level 14,
    // State 1, Line 1: Login failed for user 'admin'.

    if error.primaryMessage?.number == 4060 { /* wrong database, not a bad password */ }
}
```

Errors raised while a query is producing rows (an invalid object name, a statement
that fails partway through a batch) are thrown from the row stream rather than
ending the sequence early.

### Timeouts

```swift
let config = ConnectionConfiguration(
    host: "your_server",
    username: "your_user",
    password: "your_password",
    database: "your_database",
    loginTimeout: 15,   // seconds to wait for the login
    queryTimeout: 30    // seconds a query may run; 0 waits indefinitely
)
```

`loginTimeout` defaults to 15 seconds. Anything much tighter is a poor fit for
Azure SQL: a serverless database that has auto-paused is resumed *by* the
connection attempt, and the resume takes far longer than a warm login. Give up
too early and the failure arrives as a bare `DB-Lib error 20002 (severity 9):
TDS server connection failed`, with no server message attached, because the
connection never got far enough for SQL Server to say anything.

`queryTimeout` defaults to 0, DB-Library's own default, which waits
indefinitely. Set it if a hung query should fail rather than block forever.

Exceeding it costs you the query, not the connection: db-lib cancels the running
command on the server and the call throws, and the same connection is ready for
the next query. So a runaway `SELECT *` over a large spatial table can be cut
off without taking down the connection everything else is using.

The two are not stored the same way, which matters under concurrency:
`queryTimeout` is set on the connection itself, but DB-Library keeps the login
timeout process-wide and reads it when a connection opens, so connections opened
concurrently with different `loginTimeout` values race and the last writer wins.

The older `timeout` parameter is deprecated in favour of `loginTimeout`, which
is what it always meant.

## Upgrading FreeTDS And OpenSSL

The upgrade workflow rebuilds [FreeTDS](https://github.com/FreeTDS/freetds) and [OpenSSL](https://openssl.org) from source into `Frameworks/FreeTDS.xcframework`. FreeTDS links OpenSSL for TLS, so the two are rebuilt together and travel as a set.

The build needs Xcode with the macOS and iOS SDKs (`xcrun --sdk iphoneos --show-sdk-path` should print a path) and takes a while: five OpenSSL and FreeTDS builds, one per platform and architecture.

### 1. Update the versions in the build script

Edit [Support/buildandlinkfreetds.sh](/Users/david/dev/oliwonders/FreeTDSKit/Support/buildandlinkfreetds.sh) and change either or both of:

```bash
OPENSSL_VERSION="3.5.9"
FREETDS_VERSION="1.5.19"
OPENSSL_SHA256="..."
FREETDS_SHA256="..."
```

Take each SHA-256 from upstream rather than from your own download: openssl.org publishes `<tarball>.sha256` (also attached to the GitHub release), and freetds.org publishes `<tarball>.md5` to cross-check a second download against. The script refuses to build from a tarball that doesn't match.

A weekly GitHub Actions job (`.github/workflows/upstream-watch.yml`) opens an issue when either project publishes a newer release, flagging OpenSSL security releases.

Prefer an OpenSSL LTS release (the 3.5 series is supported into 2030) over the newest one, since a vendored archive only gets refreshed when someone runs this script.

### 2. Rebuild and re-vendor

Run:

```bash
FREETDSKIT_CODESIGN_IDENTITY="Developer ID Application: …" ./Support/buildandlinkfreetds.sh
```

What that script does:

1. Downloads the selected OpenSSL and FreeTDS release tarballs and checks their SHA-256.
2. Applies `Support/patches/freetds-*.patch` to FreeTDS (see the README there; a patch that no longer applies stops the build).
3. Configures both static-only (`no-shared` / `--disable-shared --enable-static`), with FreeTDS pointed at the OpenSSL it just built (and `pkg-config` limited to it, so a Homebrew OpenSSL can't leak in). OpenSSL's targets are `darwin64-arm64-cc` / `darwin64-x86_64-cc` for macOS, `ios64-xcrun` for iOS and `iossimulator-arm64-xcrun` / `iossimulator-x86_64-xcrun` for the Simulator; FreeTDS gets the matching `--host` and deployment-target flag (`-mmacosx-version-min`, `-mios-version-min`, `-mios-simulator-version-min`) with the SDK chosen through `SDKROOT`. On iOS FreeTDS's command-line tools, ODBC driver, server and pool are not built.
4. Installs them into `Support/build/stage-<platform>-<arch>`, configured as if installed in `/usr/local/freetdskit` so that no path from your machine ends up in the binary.
5. Does all of that once per platform and architecture (macOS arm64 and x86_64, iOS arm64, Simulator arm64 and x86_64), links each one's `libsybdb.a`, `libssl.a` and `libcrypto.a` (plus the system `libiconv`) into one dynamic library, and joins each platform's architectures with `lipo`.
6. Assembles one `FreeTDS.framework` per platform -- versioned for macOS, shallow for iOS (see [How Linking Works](#how-linking-works)) -- with library, headers, module map, privacy manifest and Info.plist, and combines the three into `Frameworks/FreeTDS.xcframework`, so the headers and library can't drift apart.
7. Runs `Support/export-apple-roots.sh` to refresh `Sources/FreeTDSKit/AppleRootCertificates.pem`. Review its diff: roots Apple added or removed since the last release.
8. Verifies every slice and fails on the first problem:
   - the architectures (`lipo -archs`);
   - each architecture's platform and minimum OS from `vtool -show-build`: `MACOS` 15.0, `IOS` 17.0 or `IOSSIMULATOR` 17.0, matching `Package.swift`;
   - the install name (`otool -D`);
   - dependencies: system libraries only (`otool -L`);
   - no build path, home folder or Xcode path in the library (`strings`);
   - the patches are in the headers, the module map is there;
   - the Info.plist (`CFBundleSupportedPlatforms`, `CFBundlePackageType`, `LSMinimumSystemVersion` or `MinimumOSVersion` and `UIDeviceFamily`), the privacy manifest, and on iOS the shallow layout.
9. With `FREETDSKIT_CODESIGN_IDENTITY` set, signs each slice's framework and then the XCFramework, and verifies the signatures. Without it the result is unsigned; sign before tagging a release.

### 3. Verify the package still links cleanly

The C target is defined in [Package.swift](/Users/david/dev/oliwonders/FreeTDSKit/Package.swift), and the FreeTDS module map is generated into the XCFramework by the build script. After replacing vendored artifacts, run:

```bash
swift build
swift test
```

And for iOS (`swift build` can only target the Mac; Xcode builds the package's `FreeTDSKit` scheme, which also runs the unit tests):

```bash
xcodebuild build -scheme FreeTDSKit -destination 'generic/platform=iOS'
xcodebuild build -scheme FreeTDSKit -destination 'generic/platform=iOS Simulator'
xcodebuild test -scheme FreeTDSKit -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
    -only-testing:FreeTDSKitTests
```

An incremental build after re-vendoring can report success while the old library is still linked in. Force a relink first:

```bash
swift package clean     # or: touch Sources/CFreeTDS/FreeTDSWrapper.c
swift build
```

If the new FreeTDS version changes transitive requirements, add them as `linkedLibrary` or `linkedFramework` settings on `CFreeTDS` in `Package.swift`. Don't use `unsafeFlags`, because it breaks every app that depends on the package.

### 4. Confirm the runtime version

The package exposes the linked library version via:

```swift
FreeTDSKit.getFreeTDSVersion()   // "freetds v1.5.19"
FreeTDSKit.versions              // freeTDS "1.5.19", openSSL "3.5.9", libiconv "1.11"
```

The unit test suite already exercises that path. Confirm it reports the version you just vendored -- if it reports a different one, the build linked a system copy rather than the archive in this repo (see [How Linking Works](#how-linking-works)).

## Linking Notes For Local Development

Most package consumers should not need a system-wide FreeTDS install because the package vendors the native artifacts. The XCFramework ships its own headers, so building the package never needs this. The helper script is only for other local tooling that wants a Homebrew FreeTDS to be discoverable through `pkg-config`.

Run:

```bash
./Support/generate_freetds_pc.sh
```

That script:

- looks for the latest Homebrew `freetds` install under `/opt/homebrew/Cellar/freetds`
- writes a `freetds.pc` file into that keg
- creates `/opt/homebrew/lib/pkgconfig/freetds.pc`
- checks the result with `pkgconf --cflags freetds`

Use it when local developer tooling cannot locate FreeTDS headers cleanly. It is not part of the normal SwiftPM consumer flow.

## Testing

### Unit tests

Run the fast unit test suite with:

```bash
swift test
```

These tests live in `Tests/FreeTDSKitTests` and cover type mapping, result handling, and the linked FreeTDS version surface. To run them on an iOS Simulator (any installed iPad or iPhone; `xcrun simctl list devices available` lists them):

```bash
xcodebuild test -scheme FreeTDSKit \
    -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
    -only-testing:FreeTDSKitTests
```

If xcodebuild reports it is "Unable to boot the Simulator", boot it first with `xcrun simctl boot <device id>` and pass `-destination id=<device id>`. The integration tests need a SQL Server reachable from the simulator and are run on macOS.

### Integration tests

Integration tests exercise real SQL Server connectivity and query behavior through the public API. They live in `Tests/FreeTDSKitIntegrationTests` and cover:

- connection success and failure cases
- query execution
- streaming queries
- `Decodable` row mapping
- binary data handling
- spatial fields: geography and geometry decoded from SQL Server's binary format and checked against `STAsText()`, including inside a `UNION`
- insert/update/delete paths

The integration test fixture creates a SQL Server 2022 container and loads `db-setup.sql`, which provisions:

- `FreeTDSKitTestDB`
- `DataTypeTest`
- `UpdateTableTest`

By default, `swift test` and Xcode will discover these tests but skip them unless `FREETDSKIT_RUN_INTEGRATION_TESTS=1` is set in the environment.

### Integration test prerequisites

- Docker Desktop
- Homebrew
- `sqlcmd`

The helper script will attempt to install missing `docker` and `sqlcmd` packages via Homebrew.

### Quick start

Run the full setup and integration suite with:

```bash
FREETDSKIT_RUN_INTEGRATION_TESTS=1 \
Tests/FreeTDSKitIntegrationTests/run-integration-tests.sh
```

That script:

1. Exports default connection settings.
2. Verifies `docker` and `sqlcmd` are installed.
3. Starts Docker if needed.
4. Launches SQL Server with `docker compose`.
5. Waits for the server to accept connections.
6. Creates and seeds the test database if it does not already exist.
7. Runs the Swift test command with the integration environment enabled.

### Environment variables

The integration suite reads these variables:

- `FREETDSKIT_RUN_INTEGRATION_TESTS` set to `1` to opt in
- `FREETDSKIT_SQL_SERVER` default: `localhost`
- `FREETDSKIT_SQL_PORT` default: `1438`
- `FREETDSKIT_SQL_USER` default: `sa`
- `FREETDSKIT_SQL_PASSWORD` default: `YourStrongPassword1`
- `FREETDSKIT_SQL_DB` default: `FreeTDSKitTestDB`

Example:

```bash
FREETDSKIT_RUN_INTEGRATION_TESTS=1 \
FREETDSKIT_SQL_PASSWORD='YourStrongPassword1' \
FREETDSKIT_SQL_PORT=1438 \
Tests/FreeTDSKitIntegrationTests/run-integration-tests.sh
```

### Running integration tests manually

If the SQL Server instance is already running and seeded, run:

```bash
FREETDSKIT_RUN_INTEGRATION_TESTS=1 \
swift test --disable-swift-testing --enable-xctest \
    --filter FreeTDSKitIntegrationTests
```

The integration targets are written with `XCTest`, so the manual command disables Swift Testing and enables XCTest explicitly.

## Forking Checklist

If you are forking this package and want a clean starting point:

1. Run `swift test`.
2. Run `FREETDSKIT_RUN_INTEGRATION_TESTS=1 Tests/FreeTDSKitIntegrationTests/run-integration-tests.sh`.
3. If you are upgrading FreeTDS, rebuild and re-vendor the C artifacts first.
4. Regenerate `Frameworks/FreeTDS.xcframework` only with `Support/buildandlinkfreetds.sh`, so its headers and archive stay in step.
5. Verify the package still builds as a standalone SwiftPM dependency before publishing your fork.

## License

See [LICENSE](/Users/david/dev/oliwonders/FreeTDSKit/LICENSE).
