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
}


#endif
