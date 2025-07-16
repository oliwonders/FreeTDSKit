import XCTest
@testable import FreeTDSKit

#if INTEGRATION_TESTS

final class FreeTDSKitIntegrationTypedTests: FreeTDSKitIntegrationTestCase {
    
    func testSpatialColumn() async throws {
        let dbConnection = try makeConnection()
        let result = try await dbConnection.execute(
            query: "SELECT SpatialColumn.STAsText() AS SpatialColumn FROM \(testTable) ORDER BY Id"
        )
        XCTAssertEqual(
            result.rows.count, 2,
            "Should return two rows for spatial column"
        )

        if let str0 = result.rows[0]["SpatialColumn"]?.string {
            XCTAssertEqual(
                str0,
                "POINT (-122.335167 47.608013)",
                "First spatial row should match expected WKT"
            )
        } else {
            XCTFail("Expected string data for first spatial row")
        }
        if let str1 = result.rows[1]["SpatialColumn"]?.string {
            XCTAssertEqual(
                str1,
                "POINT (-118.243683 34.052235)",
                "Second spatial row should match expected WKT"
            )
        } else {
            XCTFail("Expected string data for second spatial row")
        }
        await dbConnection.close()
    }
    
    func testStreamingSpatialColumn() async throws {
        let dbConnection = try makeConnection()
        var values: [String] = []
    for try await row in dbConnection.streamRows(
        query: "SELECT SpatialColumn.STAsText() AS SpatialColumn FROM \(testTable) ORDER BY Id"
    ) {
        if let str = row["SpatialColumn"]?.string {
            values.append(str)
        } else {
            XCTFail("Expected string data when streaming spatial rows")
        }
    }
    XCTAssertEqual(
        values,
        ["POINT (-122.335167 47.608013)", "POINT (-118.243683 34.052235)"],
        "Streamed spatial values should match expected WKTs"
    )
        await dbConnection.close()
    }

    func testDecodableSpatialColumn() async throws {
        struct SpatialRow: Decodable, Equatable {
            let SpatialColumn: String
        }
        let dbConnection = try TDSConnection(
            server: "\(server):\(port)",
            username: username,
            password: password,
            database: database
        )
        var rows: [SpatialRow] = []
    for try await row in dbConnection.rows(
        query: "SELECT SpatialColumn.STAsText() AS SpatialColumn FROM \(testTable) ORDER BY Id",
        as: SpatialRow.self
    ) {
            rows.append(row)
        }
    let expected = [
        SpatialRow(SpatialColumn: "POINT (-122.335167 47.608013)"),
        SpatialRow(SpatialColumn: "POINT (-118.243683 34.052235)")
    ]
        XCTAssertEqual(
            rows,
            expected,
            "Decodable spatial rows should match expected rows"
        )
        await dbConnection.close()
    }
    
    
    func testComputedSpatialColumn() async throws {
//        47.608013    -122.335167
//        34.052235    -118.243683
    }
    
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
