//
//  SQLResult
//  FreeTDSKit
//
//  Created by David Oliver on 12/28/24.
//

import Foundation

public struct SQLResult {
    public let columns: [String] // Column names
    public let rows: [[String: SQLDataType]] // Rows with typed data
    public let affectedRows: Int // Affected rows count

    public init(columns: [String], rows: [[String: SQLDataType]], affectedRows: Int) {
        self.columns = columns
        self.rows = rows
        self.affectedRows = affectedRows
    }
}
