import XCTest
@testable import FreeTDSKit

class FreeTDSKitIntegrationTestCase: XCTestCase {
    var server: String { ProcessInfo.processInfo.environment["FREETDSKIT_SQL_SERVER"] ?? "localhost" }
    var port: String { ProcessInfo.processInfo.environment["FREETDSKIT_SQL_PORT"] ?? "1438" }
    var username: String { ProcessInfo.processInfo.environment["FREETDSKIT_SQL_USER"] ?? "sa" }
    var password: String { ProcessInfo.processInfo.environment["FREETDSKIT_SQL_PASSWORD"] ?? "YourStrongPassword1" }
    var database: String { ProcessInfo.processInfo.environment["FREETDSKIT_SQL_DB"] ?? "FreeTDSKitTestDB" }
    
    var connectionString: String {
        "\(server):\(port)"
    }

    let testTable = "DataTypeTest"

    func makeConnection() throws -> TDSConnection {
        try TDSConnection(
            server: connectionString,
            username: username,
            password: password,
            database: database
        )
    }
}

struct DataTypeTestRow: Decodable {
    let Id: Int
    let CharColumn: String
    let VarCharColumn: String
    let IntColumn: Int
    let SmallIntColumn: Int16
    let BigIntColumn: Int64
    let DecimalColumn: Decimal
    let FloatColumn: Double
    let RealColumn: Float
    let BitColumn: Bool
    let DateColumn: Date
    let TimeColumn: String // or `Date` with a custom decoder
    let DateTimeColumn: Date
    let SmallDateTimeColumn: Date
    let DateTime2Column: Date
    let DateTimeOffsetColumn: String // consider `ISO8601DateFormatter` or Foundation’s `Date` + timeZone decoding
    let MoneyColumn: Decimal
    let SmallMoneyColumn: Decimal
    let NCharColumn: String
    let NVarCharColumn: String
    let BinaryColumn: Data?
    let VarBinaryColumn: Data?
    let SpatialColumn: String? // spatial types typically returned as WKT text
    let ComputedSpatialColumnLat: Double?
    let ComputedSpatialColumnLong: Double?
    let UniqueIdentifierColumn: UUID
}
