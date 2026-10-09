import XCTest
@testable import FreeTDSKit

#if !INTEGRATION_TESTS

final class FreeTDSKitIntegrationTypedTests: FreeTDSKitIntegrationTestCase {
    
    func testSpatialColumn() async throws {
        let dbConnection = try makeConnection()
        let result = try await dbConnection.execute(
            queryString: "SELECT SpatialColumn.STAsText() AS SpatialColumn FROM \(testTable) ORDER BY Id"
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
    for try await row in dbConnection.streamingQuery(
        queryString: "SELECT SpatialColumn.STAsText() AS SpatialColumn FROM \(testTable) ORDER BY Id"
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
    for try await row in dbConnection.query(
        queryString: "SELECT SpatialColumn.STAsText() AS SpatialColumn FROM \(testTable) ORDER BY Id",
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
            queryString: "SELECT ComputedSpatialColumnLat, ComputedSpatialColumnLong FROM \(testTable) ORDER BY Id"
        )
        XCTAssertEqual(result.rows.count, 2, "Should return two rows for computed spatial columns")

        // First row
        if let lat0 = result.rows[0]["ComputedSpatialColumnLat"]?.double,
           let lon0 = result.rows[0]["ComputedSpatialColumnLong"]?.double {
            XCTAssertEqual(lat0, 47.608013, accuracy: 1e-9)
            XCTAssertEqual(lon0, -122.335167, accuracy: 1e-9)
        } else {
            XCTFail("Missing computed spatial values for first row")
        }

        // Second row
        if let lat1 = result.rows[1]["ComputedSpatialColumnLat"]?.double,
           let lon1 = result.rows[1]["ComputedSpatialColumnLong"]?.double {
            XCTAssertEqual(lat1, 34.052235, accuracy: 1e-9)
            XCTAssertEqual(lon1, -118.243683, accuracy: 1e-9)
        } else {
            XCTFail("Missing computed spatial values for second row")
        }
        await db.close()
    }

    /// Verify binary and varbinary columns map to Data correctly, including NULL.
    func testBinaryColumns() async throws {
        let db = try makeConnection()
        let result = try await db.execute(
            queryString: "SELECT BinaryColumn, VarBinaryColumn FROM \(testTable) ORDER BY Id"
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

    /// uniqueidentifier arrives as 16 raw bytes with the first three groups
    /// little-endian; it must round-trip to the same textual GUID.
    func testUniqueIdentifierColumn() async throws {
        let db = try makeConnection()
        let result = try await db.execute(
            queryString: "SELECT CAST('93C91F8B-FD98-4EB2-9F48-DE9B096716F4' AS uniqueidentifier) AS G, CAST(NULL AS uniqueidentifier) AS N"
        )
        XCTAssertEqual(result.rows[0]["G"]?.uuid,
                       UUID(uuidString: "93C91F8B-FD98-4EB2-9F48-DE9B096716F4"))
        XCTAssertNil(result.rows[0]["N"]?.uuid)
        await db.close()
    }

    /// Binary values can contain zero bytes; they must not be cut off there.
    func testBinaryWithZeroBytes() async throws {
        let db = try makeConnection()
        let result = try await db.execute(
            queryString: "SELECT CAST(0x0001000200FF AS varbinary(10)) AS VB, CAST(0x01 AS binary(4)) AS B4, CAST(0x00AB00 AS varbinary(max)) AS VBMax"
        )
        XCTAssertEqual(result.rows[0]["VB"]?.binary.map(Array.init), [0x00, 0x01, 0x00, 0x02, 0x00, 0xFF])
        XCTAssertEqual(result.rows[0]["B4"]?.binary.map(Array.init), [0x01, 0x00, 0x00, 0x00])
        XCTAssertEqual(result.rows[0]["VBMax"]?.binary.map(Array.init), [0x00, 0xAB, 0x00])
        await db.close()
    }

    /// Numbers are formatted to text in C; each must be read at its real width
    /// and printed in full, not cut to the raw value's byte count.
    func testNumericLimits() async throws {
        let db = try makeConnection()
        let result = try await db.execute(queryString: """
            SELECT CAST(255 AS tinyint) AS I1, CAST(-30000 AS smallint) AS I2,
                   CAST(-2147483648 AS int) AS I4, CAST(9223372036854775807 AS bigint) AS I8,
                   CAST(-122.335167 AS float) AS F8, CAST(1.5 AS real) AS R4
            """)
        let row = result.rows[0]
        XCTAssertEqual(row["I1"]?.tinyInt, 255)
        XCTAssertEqual(row["I2"]?.smallInt, -30000)
        XCTAssertEqual(row["I4"]?.int, -2147483648)
        XCTAssertEqual(row["I8"]?.bigInt, 9223372036854775807)
        XCTAssertEqual(row["F8"]?.double, -122.335167)
        XCTAssertEqual(row["R4"]?.float, 1.5)
        await db.close()
    }
}


#endif
