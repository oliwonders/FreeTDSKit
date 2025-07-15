import XCTest

@testable import FreeTDSKit

#if INTEGRATION_TESTS

/// Integration tests require a running SQL Server (e.g. via Docker).
/// They read connection parameters from environment variables:
///   - FREETDSKIT_SQL_SERVER (default: localhost)
///   - FREETDSKIT_SQL_PORT (default: 1438)
///   - FREETDSKIT_SQL_USER (default: sa)
///   - FREETDSKIT_SQL_PASSWORD (default: YourStrongPassword1)
///   - FREETDSKIT_SQL_DB (default: FreeTDSKitTestDB)
final class FreeTDSKitIntegrationTests: FreeTDSKitIntegrationTestCase {

    func testDatabaseConnection() async throws {
        let dbConnection = try makeConnection()
        XCTAssertNotNil(dbConnection)
        await dbConnection.close()
    }

    func testBasicQuery() async throws {
        let dbConnection = try makeConnection()
        let result = try await dbConnection.execute(query: "SELECT * FROM \(testTable)")
        XCTAssertGreaterThan(result.affectedRows, 0, "\(testTable) table should not be empty")
        await dbConnection.close()
    }

    func testIdColumn() async throws {
        let dbConnection = try makeConnection()
        let result = try await dbConnection.execute(query: "SELECT Id FROM \(testTable)")
        XCTAssertEqual(result.columns.count, 1, "Column count should be 1")
        XCTAssertEqual(result.rows.first?["Id"]?.int, 1, "Row 1 id should be 1")
        await dbConnection.close()
    }

    func testColumns() async throws {
        let dbConnection = try makeConnection()
        let result = try await dbConnection.execute(query: "SELECT * FROM \(testTable)")
        XCTAssertFalse(result.columns.isEmpty, "More than one column should be returned")
        await dbConnection.close()
    }

    func testStreamingRows() async throws {
        let dbConnection = try makeConnection()
        let syncResult = try await dbConnection.execute(query: "SELECT * FROM \(testTable)")
        var streamCount = 0
        for try await _ in dbConnection.streamRows(query: "SELECT * FROM \(testTable)") {
            streamCount += 1
        }
        XCTAssertEqual(streamCount, syncResult.rows.count,
                       "Streamed row count should match synchronous result rows count")
        await dbConnection.close()
    }

    func testMappedRows() async throws {
        let dbConnection = try makeConnection()
        var ids: [Int] = []
        for try await id in dbConnection.rows(query: "SELECT Id FROM \(testTable)", map: { row in
            row["Id"]?.int ?? -1
        }) {
            ids.append(id)
        }
        let syncResult = try await dbConnection.execute(query: "SELECT Id FROM \(testTable)")
        let expected = syncResult.rows.compactMap { $0["Id"]?.int }
        XCTAssertEqual(ids, expected, "Mapped row IDs should match synchronous result")
        await dbConnection.close()
    }

    func testDecodableRows() async throws {
        struct Row: Decodable, Equatable {
            let Id: Int
        }
        let dbConnection = try makeConnection()
        var results: [Row] = []
        for try await row in dbConnection.rows(query: "SELECT Id FROM \(testTable)", as: Row.self) {
            results.append(row)
        }
        let syncResult = try await dbConnection.execute(query: "SELECT Id FROM \(testTable)")
        let expected = syncResult.rows.compactMap { dict in dict["Id"]?.int }.map { Row(Id: $0) }
        XCTAssertEqual(results, expected, "Decodable rows should match synchronous result rows")
        await dbConnection.close()
    }

   
    
    /// Retrieves all rows from the test table and prints them along with column
        /// names.  This mirrors the manual describe/print workflow that developers
        /// often use when verifying connection behaviour.
        func testDescribeAndPrintRows() async throws {
            let dbConnection = try makeConnection()
            
            let result = try await dbConnection.execute(query: "SELECT * FROM \(testTable) ORDER BY Id")

            XCTAssertGreaterThan(result.rows.count, 0, "Query should return at least one row")

            print("Columns:")
            for (index, column) in result.columns.enumerated() {
                print("Column \(index): \(column)")
            }

            print("\nRows:")
            for (rowIndex, row) in result.rows.enumerated() {
                print("Row \(rowIndex + 1):")
                for column in result.columns {
                    let raw = row[column] ?? .null
                    let value = SQLResult.Value(column: column, raw: raw)
                    print("  \(column): \(value)")
                }
            }

            await dbConnection.close()
        }


}
#endif
