# FreeTDSKit

FreeTDSKit is a Swift-native wrapper around the FreeTDS C library, providing a Swift-friendly API using only Swift types (no C) to natively connect to Microsoft SQL Server and Sybase databases and execute queries.

## Features

- Provide a Swift-friendly API using only Swift types (no C) for connecting to Microsoft SQL Server and Sybase databases.
- Execute SQL queries and process results with native Swift types.
- Leverage the capabilities of the FreeTDS library transparently under the hood.

> As of now, FreeTDSKit requires `freetds` installation via Homebrew.

```
brew install freetds
```

### Adding FreeTDS Package Config Files to Homebrew

By default FreeTDS does not include a package config file (freetds.pc), therefore Xcode cannot find the sysbdb.h librarying using <> for system headers, which is more convenient than hardcoding the path using quotes.

Running the included `Support/generate_freetds_pc.sh` file will locate the installed FreeTDS version and generate a .PC file in the install /lib/pkgconfig directly, then create a symbolic link here `/opt/homebrew/lib/pkgconfig/` to the .PC file.

```
chmod +x generate_freetds_pc.sh
./generate_freetds_pc.sh
```

> Remember to re-run after updates.

## Usage
```swift
import FreeTDSKit

// Build a configuration and open a connection
let config = TDSConnection.Configuration(
    host: "your_server",
    port: 1438,
    username: "your_user",
    password: "your_password",
    database: "your_database"
)
let connection = try TDSConnection(configuration: config)

// One-off query
let result = try await connection.execute(query: "SELECT id, name FROM users")

// Streaming rows as dictionaries
for try await row in connection.streamRows(query: "SELECT id, name FROM users") {
    print(row)
}

// Streaming rows with a mapping closure
for try await name in connection.rows(query: "SELECT name FROM users", map: { row in
    row["name"]?.string ?? ""
}) {
    print(name)
}

// Streaming rows directly to Decodable models
struct User: Decodable {
    let id: Int
    let name: String
}
for try await user in connection.rows(query: "SELECT id, name FROM users", as: User.self) {
    print(user.id, user.name)
}

// Close when you're done
await connection.close()
```
