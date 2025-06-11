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

    @Test("Test geometry spatial data WKT")
    func spatialGeometryData() {
        let wkt = "POINT(30.123456 -97.123456)"
        let cString = wkt.cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBGEOMETRY)
        if case let .spatial(value) = sqlType {
            #expect(value.value == wkt)
        } else {
            Issue.record("Expected SQLDataType.spatial")
        }
    }
    
    @Test("Test geography spatial data WKT")
    func spatialGeographyData() {
        let wkt = "POINT(30.123456 -97.123456)"
        let cString = wkt.cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBGEOGRAPHY)
        if case let .spatial(value) = sqlType {
            #expect(value.value == wkt)
        } else {
            Issue.record("Expected SQLDataType.spatial")
        }
    }
}
