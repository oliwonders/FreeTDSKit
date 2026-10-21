//
//  SQLServerSpatial.swift
//  FreeTDSKit
//

import Foundation

/// SQL Server's binary format for `geography` and `geometry` values
/// ([MS-SSCLRT]), which is what arrives when a query returns the column itself
/// rather than `.STAsText()` -- including computed values such as
/// `SpatialPoint.STBuffer(50)` and every arm of a UNION.
public enum SQLServerSpatial {

    /// The value as WKT, written as `STAsText()` writes it: x before y, so
    /// "longitude latitude" for geography. Nil when `data` isn't a geography or
    /// geometry value this handles: another user-defined type that shares the
    /// wire type (hierarchyid), or curves and FullGlobe. Z and M are dropped.
    ///
    /// Geography stores latitude first and geometry x first, and the bytes
    /// don't say which they are, so a value is read as geography when its SRID
    /// is set (geometry's default is 0) and every first coordinate is a valid
    /// latitude. A geometry value with an SRID whose x values all fall within
    /// ±90 is read with its axes swapped.
    public static func wkt(fromSerialized data: Data) -> String? {
        guard let value = Value(data) else { return nil }
        return value.wkt()
    }

    // MARK: - Format

    private struct Value {
        var points: [(first: Double, second: Double)] = []
        var figures: [(attribute: UInt8, pointOffset: Int)] = []
        var shapes: [(parent: Int, figureOffset: Int, type: UInt8)] = []
        var latitudeFirst = false

        init?(_ data: Data) {
            var reader = Reader(bytes: [UInt8](data))
            guard let srid = reader.int32(),
                  let version = reader.uint8(), version == 1 || version == 2,
                  let properties = reader.uint8()
            else { return nil }
            let extraOrdinates = (properties & 0x01 != 0 ? 1 : 0) + (properties & 0x02 != 0 ? 1 : 0)  // Z, M
            let isSinglePoint = properties & 0x08 != 0
            let isSingleSegment = properties & 0x10 != 0

            if isSinglePoint || isSingleSegment {
                // The point or line segment alone; figures and shapes implied.
                let count = isSinglePoint ? 1 : 2
                guard let points = reader.points(count), reader.skip(8 * count * extraOrdinates) else { return nil }
                self.points = points
                figures = [(attribute: 1, pointOffset: 0)]
                shapes = [(parent: -1, figureOffset: 0, type: isSinglePoint ? 1 : 2)]
            } else {
                guard let pointCount = reader.count(), let points = reader.points(pointCount),
                      reader.skip(8 * pointCount * extraOrdinates),
                      let figureCount = reader.count()
                else { return nil }
                self.points = points
                for _ in 0..<figureCount {
                    guard let attribute = reader.uint8(), let offset = reader.int32(),
                          offset >= 0, Int(offset) <= pointCount,
                          // Version 2 marks arcs (2) and composite curves (3).
                          version == 1 || attribute < 2
                    else { return nil }
                    figures.append((attribute, Int(offset)))
                }
                guard let shapeCount = reader.count(), shapeCount > 0 else { return nil }
                // The first shape is the root.
                for index in 0..<shapeCount {
                    guard let parent = reader.int32(), let figureOffset = reader.int32(), let type = reader.uint8(),
                          Int(parent) < index, Int(figureOffset) < figureCount
                    else { return nil }
                    shapes.append((Int(parent), Int(figureOffset), type))
                }
                // Version 2 may list segments (for arcs, rejected above).
                if version == 2, !reader.isAtEnd {
                    guard let segmentCount = reader.count(), reader.skip(segmentCount) else { return nil }
                }
            }
            guard reader.isAtEnd else { return nil }
            latitudeFirst = srid != 0 && points.allSatisfy { abs($0.first) <= 90 }
        }

        func wkt() -> String? {
            text(ofShape: 0)
        }

        private func text(ofShape index: Int) -> String? {
            let shape = shapes[index]
            switch shape.type {
            case 1: return "POINT " + (rings(ofShape: index).first.map { "(\($0))" } ?? "EMPTY")
            case 2: return "LINESTRING " + (rings(ofShape: index).first.map { "(\($0))" } ?? "EMPTY")
            case 3: return "POLYGON " + polygonBody(index)
            case 4: return "MULTIPOINT " + list(children(of: index).map { rings(ofShape: $0).first.map { "(\($0))" } ?? "EMPTY" })
            case 5: return "MULTILINESTRING " + list(children(of: index).map { rings(ofShape: $0).first.map { "(\($0))" } ?? "EMPTY" })
            case 6: return "MULTIPOLYGON " + list(children(of: index).map(polygonBody))
            case 7:
                let members = children(of: index).map(text(ofShape:))
                guard !members.contains(where: { $0 == nil }) else { return nil }
                return "GEOMETRYCOLLECTION " + list(members.compactMap { $0 })
            default:
                // 8-10: CircularString, CompoundCurve, CurvePolygon. 11: FullGlobe.
                return nil
            }
        }

        private func polygonBody(_ index: Int) -> String {
            list(rings(ofShape: index).map { "(\($0))" })
        }

        private func list(_ items: [String]) -> String {
            items.isEmpty ? "EMPTY" : "(" + items.joined(separator: ", ") + ")"
        }

        private func children(of index: Int) -> [Int] {
            shapes.indices.filter { shapes[$0].parent == index }
        }

        /// Each figure of a point, line or polygon shape, as "x y, x y, ...".
        /// A shape's figures run up to the next shape that has any; shapes are
        /// stored depth first.
        private func rings(ofShape index: Int) -> [String] {
            let start = shapes[index].figureOffset
            guard start >= 0 else { return [] }
            let end = shapes[(index + 1)...].first { $0.figureOffset >= 0 }?.figureOffset ?? figures.count
            return (start..<max(start, end)).map { figure in
                let first = figures[figure].pointOffset
                let last = figure + 1 < figures.count ? figures[figure + 1].pointOffset : points.count
                return (first..<max(first, last)).map(coordinate).joined(separator: ", ")
            }
        }

        private func coordinate(_ index: Int) -> String {
            let point = points[index]
            let (x, y) = latitudeFirst ? (point.second, point.first) : (point.first, point.second)
            return "\(format(x)) \(format(y))"
        }

        /// Shortest form that reads back as the same Double, without a
        /// trailing ".0" on whole numbers.
        private func format(_ value: Double) -> String {
            let text = value.description
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        }
    }

    /// Little-endian reads that fail rather than run past the end.
    private struct Reader {
        let bytes: [UInt8]
        var position = 0

        var isAtEnd: Bool { position == bytes.count }

        mutating func uint8() -> UInt8? {
            guard position < bytes.count else { return nil }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func int32() -> Int32? {
            guard let raw = fixed(4) else { return nil }
            return Int32(bitPattern: UInt32(raw))
        }

        /// A count, which must be non-negative and plausible for what's left.
        mutating func count() -> Int? {
            guard let value = int32(), value >= 0, Int(value) <= bytes.count else { return nil }
            return Int(value)
        }

        mutating func points(_ count: Int) -> [(first: Double, second: Double)]? {
            guard count >= 0, count <= (bytes.count - position) / 16 else { return nil }
            return (0..<count).map { _ in
                (Double(bitPattern: fixed(8)!), Double(bitPattern: fixed(8)!))
            }
        }

        mutating func skip(_ count: Int) -> Bool {
            guard count >= 0, count <= bytes.count - position else { return false }
            position += count
            return true
        }

        private mutating func fixed(_ size: Int) -> UInt64? {
            guard size <= bytes.count - position else { return nil }
            var value: UInt64 = 0
            for i in 0..<size {
                value |= UInt64(bytes[position + i]) << (8 * UInt64(i))
            }
            position += size
            return value
        }
    }
}
