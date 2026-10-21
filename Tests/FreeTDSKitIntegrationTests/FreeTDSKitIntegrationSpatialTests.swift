import XCTest
@testable import FreeTDSKit

/// geography and geometry columns returned as themselves -- not via
/// STAsText() -- arrive in SQL Server's binary format. Decoded, they must say
/// what SQL Server's own STAsText() says.
final class FreeTDSKitIntegrationSpatialTests: FreeTDSKitIntegrationTestCase {

    private let expressions = [
        "geography::STGeomFromText('POINT(-122.349 47.651)', 4326)",
        "geography::STGeomFromText('LINESTRING(-122.360 47.656, -122.343 47.656)', 4326)",
        "geography::STGeomFromText('POLYGON((-122.358 47.653, -122.348 47.649, -122.348 47.658, -122.358 47.658, -122.358 47.653))', 4326)",
        "geography::STGeomFromText('MULTIPOINT((-122.36 47.65), (-122.34 47.66))', 4326)",
        "geography::Point(40.7128, -74.0060, 4326).STBuffer(50)",
        "geography::STGeomFromText('POINT EMPTY', 4326)",
        "geometry::STGeomFromText('POLYGON((0 0, 10 0, 10 10, 0 10, 0 0), (2 2, 2 4, 4 4, 4 2, 2 2))', 0)",
        "geometry::STGeomFromText('MULTIPOLYGON(((0 0, 1 0, 1 1, 0 0)), ((5 5, 6 5, 6 6, 5 5)))', 0)",
        "geometry::STGeomFromText('GEOMETRYCOLLECTION(POINT(1 2), LINESTRING(3 4, 5 6))', 0)",
    ]

    func testSpatialColumnsDecodeLikeSTAsText() async throws {
        let connection = try makeConnection()
        for expression in expressions {
            let result = try await connection.execute(
                queryString: "SELECT \(expression) AS g, (\(expression)).STAsText() AS wkt"
            )
            let row = try XCTUnwrap(result.rows.first, expression)
            guard case .spatial(let decoded) = row["g"] else {
                XCTFail("\(expression): expected a spatial value, got \(String(describing: row["g"]))")
                continue
            }
            let expected = try XCTUnwrap(row["wkt"]?.string, expression)
            XCTAssertEqual(keyword(decoded.value), keyword(expected), expression)
            let decodedNumbers = numbers(decoded.value), expectedNumbers = numbers(expected)
            XCTAssertEqual(decodedNumbers.count, expectedNumbers.count, "\(expression)\n\(decoded.value)\n\(expected)")
            for (a, b) in zip(decodedNumbers, expectedNumbers) {
                XCTAssertEqual(a, b, accuracy: 1e-9, expression)
            }
        }
        await connection.close()
    }

    /// The bug this replaces: a geography column in one arm of a UNION, which
    /// STAsText() rewriting can't reach, came back as one or two garbage bytes.
    func testGeographyInAUnionDecodes() async throws {
        let connection = try makeConnection()
        let result = try await connection.execute(queryString: """
            SELECT 'a' AS Label, geography::Point(40.7, -74.0, 4326) AS Shape
            UNION ALL
            SELECT 'b', geography::Point(40.7, -74.0, 4326).STBuffer(25)
            """)
        XCTAssertEqual(result.rows.count, 2)
        for row in result.rows {
            guard case .spatial(let wkt) = row["Shape"] else {
                XCTFail("expected a spatial value, got \(String(describing: row["Shape"]))")
                continue
            }
            XCTAssertTrue(wkt.value.hasPrefix("POINT") || wkt.value.hasPrefix("POLYGON"), wkt.value)
        }
        await connection.close()
    }

    private func keyword(_ wkt: String) -> String {
        String(wkt.prefix { $0.isLetter }).uppercased()
    }

    private func numbers(_ wkt: String) -> [Double] {
        wkt.split(whereSeparator: { !"0123456789.-eE".contains($0) }).compactMap { Double($0) }
    }
}
