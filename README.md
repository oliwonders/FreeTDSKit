# FreeTDSKit

FreeTDSKit is a Swift wrapper for the FreeTDS library, enabling seamless connections to Microsoft SQL Server databases from Swift applications.

Features
    •    Establish connections to Microsoft SQL Server and Sybase databases using Swift syntax.
    •    Execute SQL queries and process results within Swift applications.
    •    Utilize the robust capabilities of the FreeTDS library through a Swift-friendly interface.
    
    
As of now, FreeTDSKit requires `freetds` installation via Homebrew. FreeTDS does not include .PC files for package config integration. 

You may need to manually specify the include and library paths when building your Swift project.

```
brew install freetds
```
    
## Usage

```
import FreeTDSKit 
```
