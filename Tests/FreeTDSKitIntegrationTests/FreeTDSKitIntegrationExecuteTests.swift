import XCTest
@testable import FreeTDSKit

#if !INTEGRATION_TESTS

/// Additional integration tests for FreeTDSKit.
/// Exercises computed spatial columns and binary data handling.
final class FreeTDSKitIntegrationExecuteTests: FreeTDSKitIntegrationTestCase {

    func testInsertIntoUpdateTable() async throws {
        let connection = try makeConnection()
        let result = try await connection.execute(
            queryString: "INSERT INTO UpdateTableTest (Text) VALUES ('Test Row')"
        )
        XCTAssertEqual(result.affectedRows, 1, "Expected one row to be inserted")
        await connection.close()
    }

    func testUpdateUpdateTable() async throws {
        let connection = try makeConnection()
        _ = try await connection.execute(
            queryString: "INSERT INTO UpdateTableTest (Text) VALUES ('Row to Update')"
        )
        let result = try await connection.execute(
            queryString: "UPDATE UpdateTableTest SET Text = 'Updated Row' WHERE Text = 'Row to Update'"
        )
        XCTAssertGreaterThanOrEqual(result.affectedRows, 1, "Expected at least one row to be updated")
        await connection.close()
    }

    func testSelectMetadataFromUpdateTable() async throws {
        let connection = try makeConnection()
        let result = try await connection.execute(
            queryString: "SELECT * FROM UpdateTableTest"
        )
        XCTAssertFalse(result.columns.isEmpty, "Expected at least one column")
        XCTAssertGreaterThanOrEqual(result.rows.count, 0, "Expected zero or more rows")
        await connection.close()
    }

    func testDeleteFromUpdateTable() async throws {
        let connection = try makeConnection()
        _ = try await connection.execute(
            queryString: "INSERT INTO UpdateTableTest (Text) VALUES ('Row to Delete')"
        )
        let result = try await connection.execute(
            queryString: "DELETE FROM UpdateTableTest WHERE Text = 'Row to Delete'"
        )
        XCTAssertGreaterThanOrEqual(result.affectedRows, 1, "Expected at least one row to be deleted")
        await connection.close()
    }
}

#endif
