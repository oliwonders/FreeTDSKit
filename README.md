# FreeTDSKit

FreeTDSKit is a Swift wrapper around the [FreeTDS](https://github.com/FreeTDS/freetds) DB-Library client, exposing a Swift-native API for connecting to Microsoft SQL Server and executing queries without pushing C types into the public interface.

> The package is still evolving, but the current layout is intentionally simple: SwiftPM builds a small C shim, links a vendored static XCFramework, and exposes the result through a Swift actor-based API.

## What Is In The Repo

- `Sources/FreeTDSKit`: Swift API surface, including `TDSConnection`, `SQLResult`, and type mapping.
- `Sources/CFreeTDS`: the C shim (`FreeTDSWrapper.c` / `.h`).
- `Frameworks/FreeTDS.xcframework`: FreeTDS and OpenSSL as one static, universal (arm64 + x86_64) archive, with the FreeTDS headers.
- `Support/buildandlinkfreetds.sh`: rebuilds OpenSSL and FreeTDS from source for both architectures and regenerates the XCFramework.
- `Support/generate_freetds_pc.sh`: generates a Homebrew `freetds.pc` file and symlink for local tooling/Xcode header discovery.
- `Tests/FreeTDSKitTests`: fast unit tests.
- `Tests/FreeTDSKitIntegrationTests`: Docker-backed SQL Server integration tests.

## How Linking Works

This package does not expect users to install FreeTDS separately. FreeTDS 1.5.19 (with FreeTDSKit's patches, see `Support/patches`) and OpenSSL 3.5.9, built statically for macOS 15.0 on both arm64 and x86_64, are merged into a single archive and shipped as `Frameworks/FreeTDS.xcframework`. The XCFramework also carries the FreeTDS headers and a `CSybDB` module map.

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
- **Nothing is left for the linker to search for.** With `-L` plus `-lsybdb`, the linker takes the first match on its search path and prefers a `.dylib` over a `.a`. An environment that exports `LIBRARY_PATH` (Homebrew setups commonly add `/opt/homebrew/lib`) would silently link a system-wide FreeTDS. The binary target hands the linker the archive directly. For the same reason the module map has no `link` directive.

To check what a build actually linked, `otool -L` should show no `libsybdb`, `libssl` or `libcrypto` entries (they are static), and `FreeTDSKit.getFreeTDSVersion()` should report the version vendored here.

Because everything is static and universal, the package is suitable for sandboxed and Mac App Store apps. Such an app still needs the `com.apple.security.network.client` entitlement to reach SQL Server, and it cannot read `/usr/local/etc/freetds.conf` or `~/.freetds.conf` from inside the sandbox.

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
against the macOS system root certificates. A server with a publicly trusted
certificate, such as Azure SQL, needs nothing extra.

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

The upgrade workflow is based on vendoring new static [FreeTDS](https://github.com/FreeTDS/freetds) and [OpenSSL](https://openssl.org) builds into `Sources/CFreeTDS`. FreeTDS links OpenSSL for TLS, so the two archives are rebuilt together and travel as a set.

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
./Support/buildandlinkfreetds.sh
```

What that script does:

1. Downloads the selected OpenSSL and FreeTDS release tarballs and checks their SHA-256.
2. Applies `Support/patches/freetds-*.patch` to FreeTDS (see the README there; a patch that no longer applies stops the build).
3. Configures both static-only (`no-shared` / `--disable-shared --enable-static`), with FreeTDS pointed at the OpenSSL it just built.
4. Installs them into `Support/build/stage-<arch>`, configured as if installed in `/usr/local/freetdskit` so that no path from your machine ends up in the binary.
5. Does all of that once per architecture (arm64, x86_64), merges each architecture's `libsybdb.a`, `libssl.a` and `libcrypto.a` into one archive with `libtool`, and joins the two with `lipo`.
6. Regenerates `Frameworks/FreeTDS.xcframework` from that archive and the freshly installed FreeTDS headers, so the headers and library can't drift apart.
7. Prints each slice's platform and deployment target, which should match the platform in `Package.swift`, and fails if the archive contains a build path or lacks the patches.

### 3. Verify the package still links cleanly

The C target is defined in [Package.swift](/Users/david/dev/oliwonders/FreeTDSKit/Package.swift), and the FreeTDS module map is generated into the XCFramework by the build script. After replacing vendored artifacts, run:

```bash
swift build
swift test
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
FreeTDSKit.getFreeTDSVersion()
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

These tests live in `Tests/FreeTDSKitTests` and cover type mapping, result handling, and the linked FreeTDS version surface.

### Integration tests

Integration tests exercise real SQL Server connectivity and query behavior through the public API. They live in `Tests/FreeTDSKitIntegrationTests` and cover:

- connection success and failure cases
- query execution
- streaming queries
- `Decodable` row mapping
- binary data handling
- spatial/geography fields
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
