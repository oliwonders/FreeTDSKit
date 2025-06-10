//
//  SQLResult
//  FreeTDSKit
//
//  Created by David Oliver on 12/28/24.
//

import Foundation

public struct SQLResult {
    public let columns: [String]  // Column names
    public let rows: [[String: SQLDataType]]  // Rows with typed data
    public let affectedRows: Int  // Affected rows count

    public init(
        columns: [String],
        rows: [[String: SQLDataType]],
        affectedRows: Int
    ) {
        self.columns = columns
        self.rows = rows
        self.affectedRows = affectedRows
    }

}

extension SQLResult {

    public subscript(_ row: Int, _ column: String) -> SQLDataType? {
        guard rows.indices.contains(row) else { return nil }
        return rows[row][column]
    }

    /// Row index + column index (uses `columns`)
    public subscript(_ row: Int, column colIndex: Int) -> SQLDataType? {
        guard rows.indices.contains(row),
            columns.indices.contains(colIndex)
        else { return nil }
        return rows[row][columns[colIndex]]
    }
}

//public extension SQLResult {
//
//    /// Row index + column name → wrapped `Value`
//    subscript(row rowIndex: Int, column columnName: String) -> Value? {
//        guard rows.indices.contains(rowIndex),
//              let raw = rows[rowIndex][columnName] else { return nil }
//        return Value(column: columnName, raw: raw)
//    }
//
//    /// Row index + column index → wrapped `Value`
//    subscript(_ row: Int, column colIndex: Int) -> Value? {
//        guard rows.indices.contains(row),
//              columns.indices.contains(colIndex) else { return nil }
//        let name = columns[colIndex]
//        guard let raw = rows[row][name] else { return nil }
//        return Value(column: name, raw: raw)
//    }
//}
extension SQLResult: Sequence {
    public typealias Element = [String: SQLDataType]
    public func makeIterator() -> IndexingIterator<[[String: SQLDataType]]> {
        rows.makeIterator()
    }
}
extension SQLResult: Sendable {}
