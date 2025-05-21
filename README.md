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

Running the included `support/generate_freetds_pc.sh` file will locate the installed FreeTDS version and generate a .PC file in the install /lib/pkgconfig directly, then create a symbolic link here `/opt/homebrew/lib/pkgconfig/` to the .PC file.

```
chmod +x generate_freetds_pc.sh
./generate_freetds_pc.sh
```

> Remember to re-run after updates.

## Usage

```
import FreeTDSKit
```
