# FreeTDSKit

FreeTDSKit is a Swift-native wrapper around the FreeTDS C library, providing a Swift-friendly API using only Swift types (no C) to natively connect to Microsoft SQL Server (no Sybase support yet) database and execute queries.

> This is an experimental implemenation and I expect to refine it along the way. 

## Features

- Provide a Swift-friendly API using only Swift types (no C) for connecting to Microsoft SQL Server.
- Execute SQL queries and process results with native Swift types.
- Leverage the capabilities of the FreeTDS library transparently under the hood.


## Usage
```swift
import FreeTDSKit

// Build a configuration and open a connection
let config = ConnectionConfiguration(
    host: "your_server",
    port: 1438,
    username: "your_user",
    password: "your_password",
    database: "your_database"
)
let connection = try TDSConnection(configuration: config)

// One-off query
let result = try await connection.execute(queryString: "SELECT id, name FROM users")

// Update using execute
let updateResult = try await connection.execute(queryString: "UPDATE users SET name = 'NewName' WHERE id = 1")
print("Updated rows: \(updateResult.affectedRows)")

// Query with Decodable models
struct User: Decodable {
    let id: Int
    let name: String
}
for try await user in connection.query(queryString: "SELECT id, name FROM users", as: User.self) {
    print(user.id, user.name)
}

// Streaming rows as dictionaries
for try await row in connection.streamingQuery(queryString: "SELECT id, name FROM users") {
    print(row)
}

// Streaming rows with a mapping closure
for try await name in connection.query(queryString: "SELECT name FROM users", map: { row in
    row["name"]?.string ?? ""
}) {
    print(name)
}

// Streaming rows directly to Decodable models
for try await user in connection.query(queryString: "SELECT id, name FROM users", as: User.self) {
    print(user.id, user.name)
}

// Close when you're done
await connection.close()

// MARK: Error Handling
// On query failures the thrown error includes the detailed SQL Server message.
do {
    _ = try await connection.execute(queryString: "SELECT * FROM NonExistentTable")
} catch {
    print(error)
    // e.g. "Query execution failed: Msg 208, Level 16, State 1, Line 1: Invalid object name 'NonExistentTable'."
}

## Integration Tests

Integration tests require Docker and a live SQL Server instance. You can run the full integration test setup and run the tests with:

```bash
Tests/FreeTDSKitIntegrationTests/run-integration-tests.sh
```

Alternatively, to run integration tests directly via Swift Package Manager:

```bash
swift test --disable-swift-testing --enable-xctest \
    --filter FreeTDSKitIntegrationTests -Xswiftc -DINTEGRATION_TESTS
```
