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

        //MARK Database Connection Tests
        func testValidDatabaseConnection() async throws {
            let dbConnection = try makeConnection()
            XCTAssertNotNil(dbConnection)
            await dbConnection.close()
        }

        func testFailedDatabaseConnectionWithBadServer() async throws {
            do {
                let connection = try TDSConnection(
                    server: "127.0.0.254",
                    username: "sa",
                    password: "YourStrongPassword1",
                    database: "FreeTDSKitTestDB"
                )
                await connection.close()
                print("❌ Expected connection to fail, but it succeeded")
                XCTFail("❌ Connection should have failed")
            } catch {
                print("✅ Connection failed as expected: \(error)")
                XCTAssertNotNil(error, "Error should not be nil")
            }
        }

        func testFailedDatabaseConnectionWithInvalidUsername() async throws {
            do {
                let connection = try TDSConnection(
                    server: "127.0.0.1:1438",
                    username: "invalidusername",
                    password: "YourStrongPassword1",
                    database: "FreeTDSKitTestDB"
                )
                await connection.close()
                XCTFail("❌ Connection should have failed")
            } catch {
                print("✅ Connection failed as expected: \(error)")
                XCTAssertNotNil(error, "❌ Error should not be nil")
            }
        }

        func testFailedDatabaseConnectionWithFailedPassword() async throws {
            do {
                let connection = try TDSConnection(
                    server: "127.0.0.1:1438",
                    username: "sa",
                    password: "invalidpassword",
                    database: "FreeTDSKitTestDB"
                )
                await connection.close()
                XCTFail("❌ Connection should have failed")
            } catch {
                print("✅ Connection failed as expected: \(error)")
                XCTAssertNotNil(error, "❌ Error should not be nil")
            }
        }

        func testFailedDatabaseConnectionWithInvalidDatabase() async throws {
            do {
                let connection = try TDSConnection(
                    server: "127.0.0.1:1438",
                    username: "sa",
                    password: "YourStrongPassword1",
                    database: "DBDoesNotExist"
                )
                await connection.close()
                XCTFail("❌ Connection should have failed")
            } catch {
                print("✅ Connection failed as expected: \(error)")
                XCTAssertNotNil(error, "❌ Error should not be nil")
            }
        }

        func testConnectionWithConfiguration() async throws {

            let configuration = ConnectionConfiguration()
            configuration.host = "127.0.0.1"
            configuration.port = 1438
            configuration.username = "sa"
            configuration.password = "YourStrongPassword1"
            configuration.database = "FreeTDSKitTestDB"
            configuration.timeout = 10

            do {
                let connection = try TDSConnection(configuration: configuration)
                XCTAssertNotNil(dbConnection)
                await connection.close()

            } catch {
                XCTFail("❌ Connection should have succeeded: \(error)")
            }
        }

        //MARK Database Query Tests

        func testBasicQuery() async throws {
            let dbConnection = try makeConnection()
            let result = try await dbConnection.execute(
                query: "SELECT * FROM \(testTable)"
            )
            XCTAssertGreaterThan(
                result.affectedRows,
                0,
                "\(testTable) table should not be empty"
            )
            await dbConnection.close()
        }

        func testIdColumn() async throws {
            let dbConnection = try makeConnection()
            let result = try await dbConnection.execute(
                query: "SELECT Id FROM \(testTable)"
            )
            XCTAssertEqual(result.columns.count, 1, "Column count should be 1")
            XCTAssertEqual(
                result.rows.first?["Id"]?.int,
                1,
                "Row 1 id should be 1"
            )
            await dbConnection.close()
        }

        func testColumns() async throws {
            let dbConnection = try makeConnection()
            let result = try await dbConnection.execute(
                query: "SELECT * FROM \(testTable)"
            )
            XCTAssertFalse(
                result.columns.isEmpty,
                "More than one column should be returned"
            )
            await dbConnection.close()
        }

        func testStreamingRows() async throws {
            let dbConnection = try makeConnection()
            let syncResult = try await dbConnection.execute(
                query: "SELECT * FROM \(testTable)"
            )
            var streamCount = 0
            for try await _ in dbConnection.streamRows(
                query: "SELECT * FROM \(testTable)"
            ) {
                streamCount += 1
            }
            XCTAssertEqual(
                streamCount,
                syncResult.rows.count,
                "Streamed row count should match synchronous result rows count"
            )
            await dbConnection.close()
        }

        func testMappedRows() async throws {
            let dbConnection = try makeConnection()
            var ids: [Int] = []
            for try await id in dbConnection.rows(
                query: "SELECT Id FROM \(testTable)",
                map: { row in
                    row["Id"]?.int ?? -1
                }
            ) {
                ids.append(id)
            }
            let syncResult = try await dbConnection.execute(
                query: "SELECT Id FROM \(testTable)"
            )
            let expected = syncResult.rows.compactMap { $0["Id"]?.int }
            XCTAssertEqual(
                ids,
                expected,
                "Mapped row IDs should match synchronous result"
            )
            await dbConnection.close()
        }

        func testDecodableRows() async throws {
            struct Row: Decodable, Equatable {
                let Id: Int
            }
            let dbConnection = try makeConnection()
            var results: [Row] = []
            for try await row in dbConnection.rows(
                query: "SELECT Id FROM \(testTable)",
                as: Row.self
            ) {
                results.append(row)
            }
            let syncResult = try await dbConnection.execute(
                query: "SELECT Id FROM \(testTable)"
            )
            let expected = syncResult.rows.compactMap { dict in dict["Id"]?.int
            }.map { Row(Id: $0) }
            XCTAssertEqual(
                results,
                expected,
                "Decodable rows should match synchronous result rows"
            )
            await dbConnection.close()
        }

        /// Retrieves all rows from the test table and prints them along with column
        /// names.  This mirrors the manual describe/print workflow that developers
        /// often use when verifying connection behaviour.
        func testDescribeAndPrintRows() async throws {
            let dbConnection = try makeConnection()

            let result = try await dbConnection.execute(
                query: "SELECT * FROM \(testTable) ORDER BY Id"
            )

            XCTAssertGreaterThan(
                result.rows.count,
                0,
                "Query should return at least one row"
            )

            //            print("Columns:")
            //            for (index, column) in result.columns.enumerated() {
            //                print("Column \(index): \(column)")
            //            }
            //
            //            print("\nRows:")
            //            for (rowIndex, row) in result.rows.enumerated() {
            //                print("Row \(rowIndex + 1):")
            //                for column in result.columns {
            //                    let raw = row[column] ?? .null
            //                    let value = SQLResult.Value(column: column, raw: raw)
            //                    print("  \(column): \(value)")
            //                }
            //            }

            await dbConnection.close()
        }

        func testInvalidQuery() async throws {

            do {
                let dbConnection = try makeConnection()
                _ = try await dbConnection.execute(
                    query: "SELECT * FROM invalidTable"
                )
                await dbConnection.close()
                XCTFail("❌ Query should have failed")
            } catch {
                print("✅ Query failed as expected: \(error)")
                XCTAssertNotNil(error, "❌ Error should not be nil")
            }
        }

    }
#endif
