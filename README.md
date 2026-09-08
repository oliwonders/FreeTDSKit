# FreeTDSKit

FreeTDSKit is a Swift wrapper around the [FreeTDS](https://github.com/FreeTDS/freetds) DB-Library client, exposing a Swift-native API for connecting to Microsoft SQL Server and executing queries without pushing C types into the public interface.

> The package is still evolving, but the current layout is intentionally simple: SwiftPM builds a small C shim, links vendored static libraries, and exposes the result through a Swift actor-based API.

## What Is In The Repo

- `Sources/FreeTDSKit`: Swift API surface, including `TDSConnection`, `SQLResult`, and type mapping.
- `Sources/CFreeTDS`: C shim plus vendored FreeTDS headers and static libraries.
- `Support/buildandlinkfreetds.sh`: rebuilds OpenSSL and FreeTDS from source and copies `libsybdb.a`, `libssl.a`, and `libcrypto.a` into the package.
- `Support/generate_freetds_pc.sh`: generates a Homebrew `freetds.pc` file and symlink for local tooling/Xcode header discovery.
- `Tests/FreeTDSKitTests`: fast unit tests.
- `Tests/FreeTDSKitIntegrationTests`: Docker-backed SQL Server integration tests.

## How Linking Works

This package does not expect user to install FreeTDS separately at build time. Instead, the package vendors the important C artifacts inside `Sources/CFreeTDS`:

- FreeTDS headers under `Sources/CFreeTDS/include`
- `libsybdb.a`
- `libssl.a`
- `libcrypto.a`

`Package.swift` builds `CFreeTDS` as a C target and passes SwiftPM linker flags pointing at that directory:

```swift
.unsafeFlags([
    "\(Context.packageDirectory)/Sources/CFreeTDS/libsybdb.a",
    "\(Context.packageDirectory)/Sources/CFreeTDS/libssl.a",
    "\(Context.packageDirectory)/Sources/CFreeTDS/libcrypto.a",
    "-liconv",
])
```

That means the package resolves as a self-contained SwiftPM dependency as long as those vendored archives and headers are kept in sync. The current archives are FreeTDS 1.5.19 and OpenSSL 3.5.8, built for macOS 15.0.

The archives are named by full path deliberately. The earlier form, `-L` plus `-lsybdb`, made the linker search: it takes the first match on the path and prefers a `.dylib` over a `.a`, so an environment that exports `LIBRARY_PATH` -- a Homebrew setup commonly adds `/opt/homebrew/lib` -- would link a system-wide FreeTDS over the vendored archive, silently and with no diagnostic:

```bash
$ otool -L .build/debug/YourApp | grep sybdb
    /opt/homebrew/opt/freetds/lib/libsybdb.5.dylib   # the system copy, not this repo's
```

A full path leaves nothing to search, so that cannot happen. If you ever need to check what a build actually linked, `otool -L` should show no `libsybdb`/`libssl`/`libcrypto` entries at all -- they are static -- and `FreeTDSKit.getFreeTDSVersion()` should report the version vendored here.

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
OPENSSL_VERSION="3.5.8"
FREETDS_VERSION="1.5.19"
```

Prefer an OpenSSL LTS release (the 3.5 series is supported into 2030) over the newest one, since a vendored archive only gets refreshed when someone runs this script.

### 2. Rebuild and re-vendor

Run:

```bash
./Support/buildandlinkfreetds.sh
```

What that script does:

1. Downloads the selected OpenSSL and FreeTDS release tarballs.
2. Configures both static-only (`no-shared` / `--disable-shared --enable-static`), with FreeTDS pointed at the OpenSSL it just built.
3. Installs them into `Support/build/static-openssl` and `Support/build/static-freetds`.
4. Copies `libsybdb.a`, `libssl.a`, and `libcrypto.a` into `Sources/CFreeTDS/`.
5. Prints the deployment target of each archive, which should match the platform in `Package.swift`.

Important limitation: the script does **not** refresh the vendored headers in `Sources/CFreeTDS/include`. They rarely change between FreeTDS patch releases -- 1.5.19 installs headers byte-identical to 1.5.16 -- but after a larger jump, diff them against `Support/build/static-freetds/include` and copy over anything that moved. A header that disagrees with `libsybdb.a` is the kind of mismatch that compiles and then misbehaves at runtime.

### 3. Verify the package still links cleanly

The C target is defined in [Package.swift](/Users/david/dev/oliwonders/FreeTDSKit/Package.swift), and the bridge module is declared in [Sources/CFreeTDS/module.modulemap](/Users/david/dev/oliwonders/FreeTDSKit/Sources/CFreeTDS/module.modulemap). After replacing vendored artifacts, run:

```bash
swift build
swift test
```

SwiftPM does not treat the vendored `.a` files as build inputs, so an incremental build after re-vendoring will happily report success while the old library is still linked in. Force a relink first:

```bash
swift package clean     # or: touch Sources/CFreeTDS/FreeTDSWrapper.c
swift build
```

If the new FreeTDS version changes transitive requirements, update the linker flags in `Package.swift` accordingly.

### 4. Confirm the runtime version

The package exposes the linked library version via:

```swift
FreeTDSKit.getFreeTDSVersion()
```

The unit test suite already exercises that path. Confirm it reports the version you just vendored -- if it reports a different one, the build linked a system copy rather than the archive in this repo (see [How Linking Works](#how-linking-works)).

## Linking Notes For Local Development

Most package consumers should not need a system-wide FreeTDS install because the package vendors the native artifacts. The extra linking helper script exists for local development on macOS, especially when Xcode or local tooling needs help finding `sybdb.h`.

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
4. Keep `Sources/CFreeTDS/include`, `libsybdb.a`, `libssl.a`, and `libcrypto.a` aligned.
5. Verify the package still builds as a standalone SwiftPM dependency before publishing your fork.

## License

See [LICENSE](/Users/david/dev/oliwonders/FreeTDSKit/LICENSE).
