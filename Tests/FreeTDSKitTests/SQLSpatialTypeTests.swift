// Copyright (c) 2025 oli/wonders & David Oliver
//
//  Licensed under the MIT License.
//
//  The full text of the license can be found in the file named LICENSE.

import CFreeTDS
import Testing
import XCTest

@testable import FreeTDSKit

@Suite("Miscellaneous SQLDataType Tests") struct SQLSpatialTypeTests {

    // geography and geometry both arrive as user-defined type 240, in SQL
    // Server's binary format, never as WKT text; SQLServerSpatialTests covers
    // decoding them. (These tests used to feed WKT text in as 240 and 241.)

    /// 241 is SQL Server's xml type, not geometry.
    @Test("xml columns are text")
    func xmlColumnIsText() {
        let xml = "<territory name=\"NY181\"/>"
        let bytes = Array(xml.utf8)
        let sqlType = bytes.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) {
                determineSQLType($0.baseAddress!, length: bytes.count, columnType: 241)
            }
        }
        guard case .text(let value) = sqlType else {
            Issue.record("Expected SQLDataType.text, got \(sqlType)")
            return
        }
        #expect(value == xml)
    }

    /// Text where binary was expected is no spatial value: kept as bytes
    /// rather than reported as WKT.
    @Test("non-spatial user-defined values stay binary")
    func wktTextAsUserDefinedTypeIsNotSpatial() {
        let bytes = Array("POINT(30.123456 -97.123456)".utf8)
        let sqlType = bytes.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) {
                determineSQLType($0.baseAddress!, length: bytes.count, columnType: SYBGEOGRAPHY)
            }
        }
        guard case .binary(let data) = sqlType else {
            Issue.record("Expected SQLDataType.binary, got \(sqlType)")
            return
        }
        #expect(data == Data(bytes))
    }
}
