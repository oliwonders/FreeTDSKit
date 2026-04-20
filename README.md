# FreeTDSKit

FreeTDSKit is a Swift wrapper around the FreeTDS DB-Library client, exposing a Swift-native API for connecting to Microsoft SQL Server and executing queries without pushing C types into the public interface.

> The package is still evolving, but the current layout is intentionally simple: SwiftPM builds a small C shim, links vendored static libraries, and exposes the result through a Swift actor-based API.

## What Is In The Repo

- `Sources/FreeTDSKit`: Swift API surface, including `TDSConnection`, `SQLResult`, and type mapping.
- `Sources/CFreeTDS`: C shim plus vendored FreeTDS headers and static libraries.
- `Support/buildandlinkfreetds.sh`: rebuilds FreeTDS from source and copies the generated headers and `libsybdb.a` into the package.
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
    "-L\(Context.packageDirectory)/Sources/CFreeTDS",
    "-lsybdb",
    "-lssl",
    "-lcrypto",
    "-liconv",
])
```

That means the package resolves as a self-contained SwiftPM dependency as long as those vendored archives and headers are kept in sync.

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

On SQL failures, the thrown error includes the detailed SQL Server message captured by the C wrapper.

## Upgrading FreeTDS

The upgrade workflow is based on vendoring a new static FreeTDS build into `Sources/CFreeTDS`.

### 1. Update the version in the build script

Edit [Support/buildandlinkfreetds.sh](/Users/david/dev/oliwonders/FreeTDSKit/Support/buildandlinkfreetds.sh) and change:

```bash
FREETDS_VERSION="1.5.2"
```

### 2. Rebuild and re-vendor FreeTDS

Run:

```bash
./Support/buildandlinkfreetds.sh
```

What that script does:

1. Downloads the selected FreeTDS release tarball.
2. Configures it with `--disable-shared --enable-static`.
3. Builds and installs it into `Support/build/static-freetds`.
4. Copies generated headers into `Sources/CFreeTDS/include`.
5. Copies `libsybdb.a` into `Sources/CFreeTDS/`.

Important limitation: the script only refreshes FreeTDS itself. This repo also vendors `libssl.a` and `libcrypto.a`, so if the new FreeTDS build needs different OpenSSL artifacts you need to refresh those archives separately and keep them compatible with the new `libsybdb.a`.

### 3. Verify the package still links cleanly

The C target is defined in [Package.swift](/Users/david/dev/oliwonders/FreeTDSKit/Package.swift), and the bridge module is declared in [Sources/CFreeTDS/module.modulemap](/Users/david/dev/oliwonders/FreeTDSKit/Sources/CFreeTDS/module.modulemap). After replacing vendored artifacts, run:

```bash
swift build
swift test
```

If the new FreeTDS version changes transitive requirements, update the linker flags in `Package.swift` accordingly.

### 4. Confirm the runtime version

The package exposes the linked library version via:

```swift
FreeTDSKit.getFreeTDSVersion()
```

The unit test suite already exercises that path.

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
