import XCTest
@testable import FreeTDSKit

#if INTEGRATION_TESTS

/// Additional integration tests for FreeTDSKit.
/// Exercises computed spatial columns and binary data handling.
final class FreeTDSKitIntegrationExtraTests: FreeTDSKitIntegrationTestCase {

    /// Verify that the computed spatial latitude/longitude columns match the source geography.
    func testComputedSpatialColumns() async throws {
        let db = try makeConnection()
        let result = try await db.execute(
            query: "SELECT ComputedSpatialColumnLat, ComputedSpatialColumnLong FROM \(testTable) ORDER BY Id"
        )
        XCTAssertEqual(result.rows.count, 2, "Should return two rows for computed spatial columns")

        // First row
        if let lat0 = result.rows[0]["ComputedSpatialColumnLat"]?.double,
           let lon0 = result.rows[0]["ComputedSpatialColumnLong"]?.double {
            // values are truncated by the C wrapper buffer to ~6 decimals
            XCTAssertEqual(lat0, 47.60801, accuracy: 1e-5)
            XCTAssertEqual(lon0, -122.335, accuracy: 1e-5)
        } else {
            XCTFail("Missing computed spatial values for first row")
        }

        // Second row
        if let lat1 = result.rows[1]["ComputedSpatialColumnLat"]?.double,
           let lon1 = result.rows[1]["ComputedSpatialColumnLong"]?.double {
            XCTAssertEqual(lat1, 34.05223, accuracy: 1e-5)
            XCTAssertEqual(lon1, -118.243, accuracy: 1e-5)
        } else {
            XCTFail("Missing computed spatial values for second row")
        }
        await db.close()
    }

    /// Verify binary and varbinary columns map to Data correctly, including NULL.
    func testBinaryColumns() async throws {
        let db = try makeConnection()
        let result = try await db.execute(
            query: "SELECT BinaryColumn, VarBinaryColumn FROM \(testTable) ORDER BY Id"
        )
        XCTAssertEqual(result.rows.count, 2, "Should return two rows for binary columns")

        // First row: both fixed and variable binary non-null
        if let dataFixed = result.rows[0]["BinaryColumn"]?.binary {
            XCTAssertEqual(Array(dataFixed), [1,2,3,4,5,6,7,8,9,10])
        } else {
            XCTFail("Missing BinaryColumn for first row")
        }
        if let dataVar = result.rows[0]["VarBinaryColumn"]?.binary {
            XCTAssertEqual(Array(dataVar), [1,2,3])
        } else {
            XCTFail("Missing VarBinaryColumn for first row")
        }

        // Second row: VarBinaryColumn is empty (NULL maps to zero-length)
        XCTAssertEqual(result.rows[1]["VarBinaryColumn"]?.binary?.count, 0,
                       "VarBinaryColumn should be empty for second row")
        await db.close()
    }

}

#endif