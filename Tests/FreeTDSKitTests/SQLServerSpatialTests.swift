import Foundation
import Testing
@testable import FreeTDSKit

/// Values built by hand from the [MS-SSCLRT] layout. The integration tests
/// check the decoder against SQL Server's own STAsText().
@Suite("SQL Server spatial binary")
struct SQLServerSpatialTests {

    /// SRID, version, properties, then either the lone point/segment or the
    /// full points / figures / shapes lists.
    private func serialize(
        srid: Int32, version: UInt8 = 1, properties: UInt8,
        points: [(Double, Double)], figures: [(UInt8, Int32)]? = nil,
        shapes: [(Int32, Int32, UInt8)]? = nil, extra: [UInt8] = []
    ) -> Data {
        var bytes: [UInt8] = []
        func int32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { bytes += $0 } }
        func double(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { bytes += $0 } }
        int32(srid)
        bytes += [version, properties]
        if let figures, let shapes {
            int32(Int32(points.count))
            points.forEach { double($0.0); double($0.1) }
            int32(Int32(figures.count))
            figures.forEach { bytes.append($0.0); int32($0.1) }
            int32(Int32(shapes.count))
            shapes.forEach { int32($0.0); int32($0.1); bytes.append($0.2) }
        } else {
            points.forEach { double($0.0); double($0.1) }
        }
        return Data(bytes + extra)
    }

    private let valid: UInt8 = 0x04, singlePoint: UInt8 = 0x08, singleSegment: UInt8 = 0x10, hasZ: UInt8 = 0x01

    // MARK: Points and lines

    /// The example in [MS-SSCLRT]: geometry POINT (1 2), SRID 0.
    @Test func specificationExample() {
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x01, 0x0C,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x3F,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40]
        #expect(SQLServerSpatial.wkt(fromSerialized: Data(bytes)) == "POINT (1 2)")
    }

    /// Geography stores latitude first; WKT wants longitude first.
    @Test func geographyPointIsLongitudeFirst() {
        let data = serialize(srid: 4326, properties: valid | singlePoint, points: [(47.65, -122.35)])
        #expect(SQLServerSpatial.wkt(fromSerialized: data) == "POINT (-122.35 47.65)")
    }

    /// Geometry with an SRID whose x can't be a latitude keeps its order.
    @Test func geometryWithSRIDKeepsItsOrder() {
        let data = serialize(srid: 4326, properties: valid | singlePoint, points: [(-100, 40)])
        #expect(SQLServerSpatial.wkt(fromSerialized: data) == "POINT (-100 40)")
    }

    @Test func zValuesAreSkipped() {
        var data = serialize(srid: 4326, properties: valid | singlePoint | hasZ, points: [(40, -74)])
        withUnsafeBytes(of: (12.5).bitPattern.littleEndian) { data.append(contentsOf: $0) }
        #expect(SQLServerSpatial.wkt(fromSerialized: data) == "POINT (-74 40)")
    }

    @Test func singleLineSegment() {
        let data = serialize(srid: 0, properties: valid | singleSegment, points: [(0, 0), (3, 4)])
        #expect(SQLServerSpatial.wkt(fromSerialized: data) == "LINESTRING (0 0, 3 4)")
    }

    @Test func emptyPoint() {
        let data = serialize(srid: 4326, properties: valid, points: [], figures: [], shapes: [(-1, -1, 1)])
        #expect(SQLServerSpatial.wkt(fromSerialized: data) == "POINT EMPTY")
    }

    // MARK: Polygons

    @Test func geographyPolygon() {
        let ring: [(Double, Double)] = [(47.653, -122.358), (47.649, -122.348), (47.658, -122.348),
                                        (47.658, -122.358), (47.653, -122.358)]
        let data = serialize(srid: 4326, properties: valid, points: ring,
                             figures: [(2, 0)], shapes: [(-1, 0, 3)])
        #expect(SQLServerSpatial.wkt(fromSerialized: data)
                == "POLYGON ((-122.358 47.653, -122.348 47.649, -122.348 47.658, -122.358 47.658, -122.358 47.653))")
    }

    @Test func polygonWithHole() {
        let outer: [(Double, Double)] = [(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)]
        let hole: [(Double, Double)] = [(2, 2), (2, 4), (4, 4), (4, 2), (2, 2)]
        let data = serialize(srid: 0, properties: valid, points: outer + hole,
                             figures: [(2, 0), (0, 5)], shapes: [(-1, 0, 3)])
        #expect(SQLServerSpatial.wkt(fromSerialized: data)
                == "POLYGON ((0 0, 10 0, 10 10, 0 10, 0 0), (2 2, 2 4, 4 4, 4 2, 2 2))")
    }

    @Test func multiPolygon() {
        let a: [(Double, Double)] = [(0, 0), (1, 0), (1, 1), (0, 0)]
        let b: [(Double, Double)] = [(5, 5), (6, 5), (6, 6), (5, 5)]
        let data = serialize(srid: 0, properties: valid, points: a + b,
                             figures: [(2, 0), (2, 4)], shapes: [(-1, 0, 6), (0, 0, 3), (0, 1, 3)])
        #expect(SQLServerSpatial.wkt(fromSerialized: data)
                == "MULTIPOLYGON (((0 0, 1 0, 1 1, 0 0)), ((5 5, 6 5, 6 6, 5 5)))")
    }

    @Test func geometryCollection() {
        let data = serialize(srid: 0, properties: valid, points: [(1, 2), (3, 4), (5, 6)],
                             figures: [(1, 0), (1, 1)], shapes: [(-1, 0, 7), (0, 0, 1), (0, 1, 2)])
        #expect(SQLServerSpatial.wkt(fromSerialized: data)
                == "GEOMETRYCOLLECTION (POINT (1 2), LINESTRING (3 4, 5 6))")
    }

    // MARK: Not spatial, or not handled

    @Test func otherUserDefinedTypesAreRejected() {
        #expect(SQLServerSpatial.wkt(fromSerialized: Data([0x58])) == nil)              // a hierarchyid
        #expect(SQLServerSpatial.wkt(fromSerialized: Data()) == nil)
    }

    @Test func truncatedOrPaddedValuesAreRejected() {
        let full = serialize(srid: 4326, properties: valid | singlePoint, points: [(1, 2)])
        #expect(SQLServerSpatial.wkt(fromSerialized: full.dropLast()) == nil)
        #expect(SQLServerSpatial.wkt(fromSerialized: full + Data([0])) == nil)
    }

    @Test func curvesAndUnknownVersionsAreRejected() {
        let circular = serialize(srid: 0, version: 2, properties: valid, points: [(0, 0), (1, 1), (2, 0)],
                                 figures: [(2, 0)], shapes: [(-1, 0, 8)])
        #expect(SQLServerSpatial.wkt(fromSerialized: circular) == nil)
        let version3 = serialize(srid: 0, version: 3, properties: valid | singlePoint, points: [(1, 2)])
        #expect(SQLServerSpatial.wkt(fromSerialized: version3) == nil)
    }

    // MARK: Column decoding

    /// The SRID's zero bytes used to end the value: it was read as a C string.
    @Test func userDefinedTypeColumnDecodesToWKT() {
        let data = serialize(srid: 4326, properties: valid | singlePoint, points: [(47.65, -122.35)])
        let value = data.withUnsafeBytes { raw in
            determineSQLType(raw.bindMemory(to: CChar.self).baseAddress!, length: data.count, columnType: SYBGEOGRAPHY)
        }
        guard case .spatial(let wkt) = value else {
            Issue.record("expected .spatial, got \(value)")
            return
        }
        #expect(wkt.value == "POINT (-122.35 47.65)")
    }

    @Test func otherUserDefinedTypeColumnStaysBinary() {
        let data = Data([0x58, 0x00, 0x01])
        let value = data.withUnsafeBytes { raw in
            determineSQLType(raw.bindMemory(to: CChar.self).baseAddress!, length: data.count, columnType: SYBGEOGRAPHY)
        }
        guard case .binary(let bytes) = value else {
            Issue.record("expected .binary, got \(value)")
            return
        }
        #expect(bytes == data)
    }
}
