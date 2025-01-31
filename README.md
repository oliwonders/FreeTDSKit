# FreeTDSKit

FreeTDSKit is a Swift wrapper for the FreeTDS library, enabling seamless connections to Microsoft SQL Server databases from Swift applications.

## Features

- Establish connections to Microsoft SQL Server and Sybase databases using Swift syntax.
- Execute SQL queries and process results within Swift applications.
- Utilize the robust capabilities of the FreeTDS library through a Swift-friendly interface.

> As of now, FreeTDSKit requires `freetds` installation via Homebrew.

```
brew install freetds
```

### Adding FreeTDS Package Config Files to Homebrew

By default FreeTDS does not include a package config file (freetds.pc), therefore Xcode cannot find the sysbdb.h librarying using <> for system headers, which is more convenient than hardcoding the path using quotes.

Running the included `support/generate_freetds_pc.sh` file will locate the installed FreeTDS version and generate a .PC file in the install /lib/pkgconfig directly, then create a symbolic link here `/opt/homebrew/lib/pkgconfig/`.

```
chmod +x generate_freetds_pc.sh
./generate_freetds_pc.sh
```

> Remember to re-run after updates.

## Usage

```
import FreeTDSKit
```
