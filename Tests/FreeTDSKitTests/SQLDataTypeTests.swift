// Copyright (c) 2025 oli/wonders & David Oliver
//
//  Licensed under the MIT License.
//
//  The full text of the license can be found in the file named LICENSE.

import CFreeTDS
import Testing
import XCTest

@testable import FreeTDSKit

@Suite("Miscellaneous SQLDataType Tests") struct SQLDataTypeTests {

    @Test
    func uniqueIdentifier() {
        let cString: [CChar] = "354E427F-F042-445B-A9F0-E19540E036B9".cString(
            using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 36)  // SmallMoney type
        if case let .uniqueidentifier(value) = sqlType {
            #expect(
                value
                    == UUID(uuidString: "354E427F-F042-445B-A9F0-E19540E036B9"))
        } else {
            Issue.record("Expected SQLDataType.uniqueidentifier")
        }
    }


    @Test
    func determineMoney() {
        let cString: [CChar] = "12345.67".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 60)  // Money type
        if case let .money(value) = sqlType {
            #expect(value == Decimal(12345.67))
        } else {
            Issue.record("Expected SQLDataType.money")
        }
    }

    @Test
    func determineSmallMoney() {
        let cString: [CChar] = "1234.56".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBMONEY)  // SmallMoney type
        if case let .money(value) = sqlType {
            #expect(value == Decimal(1234.56).rounded(scale: 2))
        } else {
            Issue.record("Expected SQLDataType.smallMoney")
        }
    }

    @Test
    func float() {
        let cString: [CChar] = "3.14159".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBFLT8)
        if case let .double(value) = sqlType {
            #expect(abs(value - 3.14159) < 0.00001)
        } else {
            Issue.record("Expected SQLDataType.double")
        }
    }

    @Test("Test binary data")
    func binaryData() {
        let testData: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F]  // "Hello" in hex
        let cString = testData.map { CChar(bitPattern: $0) }
        let sqlType = determineSQLType(cString, columnType: SYBBINARY)
        if case let .binary(value) = sqlType {
            #expect(value.count == 5)
            #expect(value == Data(testData))
        } else {
            Issue.record("Expected SQLDataType.binary")
        }
    }

    @Test("Test decimal precision")
    func decimalPrecision() {
        let cString: [CChar] = "123456.789".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBDECIMAL)
        if case let .decimal(value) = sqlType {
            #expect(value == Decimal(string: "123456.789"))
            #expect(value.description == "123456.789")
        } else {
            Issue.record("Expected SQLDataType.decimal")
        }
    }

  
}
